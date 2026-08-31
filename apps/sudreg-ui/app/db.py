from __future__ import annotations

from contextlib import contextmanager
from typing import Any, Iterator

import psycopg
from psycopg.rows import dict_row

from .config import settings


@contextmanager
def get_conn() -> Iterator[psycopg.Connection]:
    conn = psycopg.connect(
        settings.database_url,
        row_factory=dict_row,
        connect_timeout=5,
    )
    try:
        yield conn
    finally:
        conn.close()


def _digits_only(s: str) -> str:
    return "".join(ch for ch in s if ch.isdigit())


def build_company_filters(
    q: str | None,
    status: str | None,
    include_deleted: bool,
    alias: str = "",
    activity: str | None = None,
) -> tuple[str, list[Any]]:
    prefix = f"{alias}." if alias else ""
    clauses: list[str] = []
    params: list[Any] = []

    if not include_deleted:
        clauses.append(f"NOT {prefix}deleted")

    if status:
        clauses.append(f"{prefix}status = %s")
        params.append(status)

    act = (activity or "").strip()
    if act:
        # Match pretežita OR bilo koja stavka u company_activities
        mbs_ref = f"{prefix}mbs"
        clauses.append(
            f"""(
              {prefix}pretezita_djelatnost = %s
              OR EXISTS (
                SELECT 1 FROM company_activities a
                WHERE a.mbs = {mbs_ref} AND a.activity = %s
              )
            )"""
        )
        params.extend([act, act])

    qq = (q or "").strip()
    if qq:
        digits = _digits_only(qq)
        if len(digits) == 11 and digits == qq.replace(" ", ""):
            clauses.append(f"{prefix}oib = %s")
            params.append(digits)
        elif digits and digits == qq.replace(" ", "") and len(digits) >= 6:
            clauses.append(f"({prefix}mbs = %s OR {prefix}oib = %s)")
            params.extend([digits, digits])
        else:
            clauses.append(
                f"({prefix}naziv ILIKE %s OR {prefix}naziv_kraci ILIKE %s OR coalesce({prefix}adresa,'') ILIKE %s"
                f" OR coalesce({prefix}email,'') ILIKE %s OR coalesce({prefix}website,'') ILIKE %s)"
            )
            like = f"%{qq}%"
            params.extend([like, like, like, like, like])

    where = ("WHERE " + " AND ".join(clauses)) if clauses else ""
    return where, params


_activity_cache: dict[str, Any] = {"at": 0.0, "rows": []}


def list_activity_options(limit: int = 5000) -> list[dict[str, Any]]:
    """Dropdown: pretežite djelatnosti (s brojem firmi), cache 10 min."""
    import time

    from .nkd import format_activity

    now = time.time()
    if _activity_cache["rows"] and (now - float(_activity_cache["at"])) < 600:
        return _activity_cache["rows"]

    sql = """
      SELECT pretezita_djelatnost AS activity, count(*)::int AS n
      FROM companies
      WHERE pretezita_djelatnost IS NOT NULL
        AND length(btrim(pretezita_djelatnost)) > 0
        AND NOT deleted
      GROUP BY pretezita_djelatnost
      ORDER BY n DESC, pretezita_djelatnost
      LIMIT %s
    """
    with get_conn() as conn:
        rows = conn.execute(sql, (limit,)).fetchall()
    enriched = []
    for r in rows:
        item = dict(r)
        item["label"] = format_activity(item.get("activity"), max_title=70)
        enriched.append(item)
    _activity_cache["at"] = now
    _activity_cache["rows"] = enriched
    return enriched


def list_companies(
    q: str | None = None,
    status: str | None = None,
    include_deleted: bool = False,
    activity: str | None = None,
    page: int = 1,
    page_size: int = 25,
) -> dict[str, Any]:
    from . import crm

    page = max(1, page)
    page_size = max(1, min(page_size, settings.page_size_max))
    offset = (page - 1) * page_size
    where, params = build_company_filters(
        q, status, include_deleted, alias="c", activity=activity
    )

    sql = f"""
      SELECT c.mbs, c.oib, c.status, c.deleted, c.naziv, c.naziv_kraci, c.adresa,
             c.pravni_oblik, c.pretezita_djelatnost, c.email, c.website,
             c.snapshot_id, c.updated_at, c.data_changed_at, c.fetched_at,
             (
               SELECT a.activity
               FROM company_activities a
               WHERE a.mbs = c.mbs AND a.is_primary
               ORDER BY a.sort_order, a.id
               LIMIT 1
             ) AS primary_activity,
             (
               SELECT count(*)::int
               FROM company_activities a
               WHERE a.mbs = c.mbs
             ) AS activities_count
      FROM companies c
      {where}
      ORDER BY c.naziv NULLS LAST, c.mbs
      LIMIT %s OFFSET %s
    """
    count_sql = f"SELECT count(*)::bigint AS n FROM companies c {where}"

    with get_conn() as conn:
        total = conn.execute(count_sql, params).fetchone()["n"]
        rows = conn.execute(sql, [*params, page_size, offset]).fetchall()

    rows = [dict(r) for r in rows]
    try:
        crm_map = crm.get_websites_by_mbs([r["mbs"] for r in rows])
    except Exception:
        crm_map = {}
    for r in rows:
        r["sudreg_website"] = r.get("website")
        crm_row = crm_map.get(r["mbs"])
        r["crm_website"] = crm_row
        r["crm_websites"] = (crm_row or {}).get("all") or []
        r["crm_domain_count"] = (crm_row or {}).get("domain_count") or 0
        if crm_row and crm_row.get("website"):
            r["website"] = crm_row["website"]
            r["website_source"] = "crm"
        elif r.get("website"):
            r["website_source"] = "sudreg"
        else:
            r["website_source"] = None

    pages = max(1, (total + page_size - 1) // page_size) if total else 1
    return {
        "rows": rows,
        "total": total,
        "page": page,
        "page_size": page_size,
        "pages": pages,
        "has_prev": page > 1,
        "has_next": page < pages,
    }


def get_company(mbs: str) -> dict[str, Any] | None:
    with get_conn() as conn:
        company = conn.execute(
            """
            SELECT *
            FROM companies
            WHERE mbs = %s
            """,
            (mbs,),
        ).fetchone()
        if not company:
            return None

        people = conn.execute(
            """
            SELECT person_type, ime, oib, tekst, uloge, sort_order
            FROM company_people
            WHERE mbs = %s
            ORDER BY person_type, sort_order, id
            """,
            (mbs,),
        ).fetchall()

        activities = conn.execute(
            """
            SELECT activity, is_primary, sort_order
            FROM company_activities
            WHERE mbs = %s
            ORDER BY is_primary DESC, sort_order, id
            LIMIT 200
            """,
            (mbs,),
        ).fetchall()

        relations = conn.execute(
            """
            SELECT tekst, sort_order
            FROM company_legal_relations
            WHERE mbs = %s
            ORDER BY sort_order, id
            LIMIT 100
            """,
            (mbs,),
        ).fetchall()

        reports = conn.execute(
            """
            SELECT datum_predaje, godina, obracunsko_razdoblje, vrsta_izvjestaja
            FROM company_financial_reports
            WHERE mbs = %s
            ORDER BY sort_order, id
            LIMIT 50
            """,
            (mbs,),
        ).fetchall()

        recent_changes = conn.execute(
            """
            SELECT snapshot_id, vrijeme, scn
            FROM promjene
            WHERE mbs = %s
            ORDER BY vrijeme DESC NULLS LAST
            LIMIT 20
            """,
            (mbs,),
        ).fetchall()

        try:
            change_log = conn.execute(
                """
                SELECT id, field_name, old_value, new_value, snapshot_id, source, changed_at
                FROM company_change_log
                WHERE mbs = %s
                ORDER BY changed_at DESC, id DESC
                LIMIT 50
                """,
                (mbs,),
            ).fetchall()
        except Exception:
            change_log = []

    company = dict(company)
    company["sudreg_website"] = company.get("website")
    try:
        from . import crm

        all_sites = crm.list_websites_for_mbs(company["mbs"])
        crm_row = next((x for x in all_sites if x.get("is_primary")), None)
        if not crm_row and all_sites:
            crm_row = all_sites[0]
    except Exception:
        crm_row = None
        all_sites = []
    company["crm_website"] = crm_row
    company["crm_websites"] = all_sites
    if crm_row and crm_row.get("website"):
        company["website"] = crm_row["website"]
        company["website_source"] = "crm"
    elif company.get("website"):
        company["website_source"] = "sudreg"
    else:
        company["website_source"] = None

    return {
        "company": company,
        "people": people,
        "activities": activities,
        "relations": relations,
        "reports": reports,
        "recent_changes": recent_changes,
        "change_log": change_log,
    }


def list_statuses() -> list[str]:
    with get_conn() as conn:
        rows = conn.execute(
            """
            SELECT DISTINCT status
            FROM companies
            WHERE status IS NOT NULL AND btrim(status) <> ''
            ORDER BY status
            LIMIT 50
            """
        ).fetchall()
    return [r["status"] for r in rows]


def db_stats() -> dict[str, Any]:
    with get_conn() as conn:
        row = conn.execute(
            """
            SELECT
              (SELECT count(*) FROM companies) AS companies,
              (SELECT count(*) FROM company_people) AS people,
              (SELECT count(*) FROM company_activities) AS activities,
              (SELECT value FROM sync_state WHERE key = 'last_imported_snapshot_id') AS last_snapshot
            """
        ).fetchone()
    return row or {}


def update_company_website(
    mbs: str,
    website: str,
    *,
    oib: str | None = None,
    confidence: str | None = None,
    evidence_url: str | None = None,
    score: int | None = None,
    verified_by: str | None = None,
    is_primary: bool = True,
    role: str | None = None,
) -> bool:
    """Spremi domenu u CRM bazu (ne u sudreg.companies)."""
    from . import crm

    row = crm.upsert_website(
        mbs=mbs,
        website=website,
        oib=oib,
        source="web_finder",
        confidence=confidence,
        evidence_url=evidence_url,
        score=score,
        verified_by=verified_by,
        is_primary=is_primary,
        role=role,
    )
    return bool(row)


def list_company_change_log(mbs: str, limit: int = 50) -> list[dict[str, Any]]:
    with get_conn() as conn:
        return conn.execute(
            """
            SELECT id, field_name, old_value, new_value, snapshot_id, source, changed_at
            FROM company_change_log
            WHERE mbs = %s
            ORDER BY changed_at DESC, id DESC
            LIMIT %s
            """,
            (mbs, limit),
        ).fetchall()
