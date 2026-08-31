from __future__ import annotations

from contextlib import contextmanager
from typing import Any, Iterator
from urllib.parse import urlparse, urlunparse

import psycopg
from psycopg.rows import dict_row

from .config import settings


def _derive_crm_url() -> str:
    if settings.crm_database_url:
        return settings.crm_database_url
    p = urlparse(settings.database_url)
    return urlunparse((p.scheme, p.netloc, "/oriphiel_crm", "", "", ""))


@contextmanager
def get_crm_conn() -> Iterator[psycopg.Connection]:
    conn = psycopg.connect(
        _derive_crm_url(),
        row_factory=dict_row,
        connect_timeout=5,
    )
    try:
        yield conn
    finally:
        conn.close()


def normalize_website(url: str) -> str:
    website = (url or "").strip()
    if not website:
        return ""
    if not website.startswith(("http://", "https://")):
        website = "https://" + website
    root = website.rstrip("/") + "/"
    return root


def _host_key(url: str) -> str:
    try:
        host = urlparse(url).netloc.lower().removeprefix("www.")
        return host.split(":")[0]
    except Exception:
        return ""


def list_websites_for_mbs(mbs: str) -> list[dict[str, Any]]:
    with get_crm_conn() as conn:
        rows = conn.execute(
            """
            SELECT id, mbs, oib, website, is_primary, role, source, confidence,
                   evidence_url, score, verified_by, notes, created_at, updated_at
            FROM company_websites
            WHERE mbs = %s
            ORDER BY is_primary DESC, score DESC NULLS LAST, updated_at DESC
            """,
            (mbs,),
        ).fetchall()
    return [dict(r) for r in rows]


def get_primary_website(mbs: str) -> dict[str, Any] | None:
    rows = list_websites_for_mbs(mbs)
    if not rows:
        return None
    for row in rows:
        if row.get("is_primary"):
            return row
    return rows[0]


def get_website(mbs: str) -> dict[str, Any] | None:
    """Glavna domena (backward compat)."""
    return get_primary_website(mbs)


def get_websites_by_mbs(mbs_list: list[str]) -> dict[str, dict[str, Any]]:
    """Za listu tvrtki: primary + svi URL-ovi."""
    if not mbs_list:
        return {}
    with get_crm_conn() as conn:
        rows = conn.execute(
            """
            SELECT id, mbs, oib, website, is_primary, role, source, confidence,
                   evidence_url, score, verified_by, updated_at
            FROM company_websites
            WHERE mbs = ANY(%s)
            ORDER BY mbs, is_primary DESC, score DESC NULLS LAST
            """,
            (mbs_list,),
        ).fetchall()

    grouped: dict[str, list[dict[str, Any]]] = {}
    for r in rows:
        grouped.setdefault(r["mbs"], []).append(dict(r))

    out: dict[str, dict[str, Any]] = {}
    for mbs, items in grouped.items():
        primary = next((x for x in items if x.get("is_primary")), items[0])
        others = [x for x in items if x["website"] != primary["website"]]
        out[mbs] = {
            **primary,
            "all": items,
            "others": others,
            "domain_count": len(items),
        }
    return out


def _clear_primary(conn: psycopg.Connection, mbs: str, except_website: str | None = None) -> None:
    if except_website:
        conn.execute(
            """
            UPDATE company_websites
            SET is_primary = FALSE, updated_at = NOW()
            WHERE mbs = %s AND website <> %s AND is_primary
            """,
            (mbs, except_website),
        )
    else:
        conn.execute(
            """
            UPDATE company_websites
            SET is_primary = FALSE, updated_at = NOW()
            WHERE mbs = %s AND is_primary
            """,
            (mbs,),
        )


def upsert_website(
    *,
    mbs: str,
    website: str,
    oib: str | None = None,
    source: str = "web_finder",
    confidence: str | None = None,
    evidence_url: str | None = None,
    score: int | None = None,
    verified_by: str | None = None,
    is_primary: bool | None = None,
    role: str | None = None,
) -> dict[str, Any] | None:
    website = normalize_website(website)
    if not website or not mbs:
        return None

    with get_crm_conn() as conn:
        existing = conn.execute(
            "SELECT id, is_primary FROM company_websites WHERE mbs = %s AND website = %s",
            (mbs, website),
        ).fetchone()
        has_primary = conn.execute(
            "SELECT 1 FROM company_websites WHERE mbs = %s AND is_primary LIMIT 1",
            (mbs,),
        ).fetchone()

        if is_primary is None:
            is_primary = not has_primary if not existing else bool(existing["is_primary"])

        if is_primary:
            _clear_primary(conn, mbs, except_website=website)

        row = conn.execute(
            """
            INSERT INTO company_websites (
              mbs, oib, website, is_primary, role, source, confidence,
              evidence_url, score, verified_by, updated_at
            ) VALUES (
              %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW()
            )
            ON CONFLICT (mbs, website) DO UPDATE SET
              oib = COALESCE(EXCLUDED.oib, company_websites.oib),
              is_primary = EXCLUDED.is_primary,
              role = COALESCE(EXCLUDED.role, company_websites.role),
              source = EXCLUDED.source,
              confidence = EXCLUDED.confidence,
              evidence_url = EXCLUDED.evidence_url,
              score = EXCLUDED.score,
              verified_by = COALESCE(EXCLUDED.verified_by, company_websites.verified_by),
              updated_at = NOW()
            RETURNING id, mbs, website, is_primary, role, source, confidence, updated_at
            """,
            (
                mbs,
                oib,
                website,
                is_primary,
                role,
                source,
                confidence,
                evidence_url,
                score,
                verified_by,
            ),
        ).fetchone()
        conn.commit()
    return dict(row) if row else None


def save_ranked_websites(
    *,
    mbs: str,
    ranked: list[dict[str, Any]],
    oib: str | None = None,
    source: str = "web_finder_batch",
    verified_by: str | None = "worker",
    min_score: int = 60,
) -> list[dict[str, Any]]:
    """Spremi sve kvalificirane domene; prva u rang-u postaje glavna."""
    saved: list[dict[str, Any]] = []
    qualifying = [
        r
        for r in ranked
        if r.get("website") and int(r.get("score") or 0) >= min_score
    ]
    if not qualifying:
        return saved

    with get_crm_conn() as conn:
        _clear_primary(conn, mbs)
        for i, item in enumerate(qualifying):
            website = normalize_website(str(item["website"]))
            row = conn.execute(
                """
                INSERT INTO company_websites (
                  mbs, oib, website, is_primary, role, source, confidence,
                  evidence_url, score, verified_by, updated_at
                ) VALUES (
                  %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW()
                )
                ON CONFLICT (mbs, website) DO UPDATE SET
                  oib = COALESCE(EXCLUDED.oib, company_websites.oib),
                  is_primary = EXCLUDED.is_primary,
                  role = COALESCE(EXCLUDED.role, company_websites.role),
                  source = EXCLUDED.source,
                  confidence = EXCLUDED.confidence,
                  evidence_url = EXCLUDED.evidence_url,
                  score = EXCLUDED.score,
                  verified_by = COALESCE(EXCLUDED.verified_by, company_websites.verified_by),
                  updated_at = NOW()
                RETURNING id, mbs, website, is_primary, role, score
                """,
                (
                    mbs,
                    oib,
                    website,
                    i == 0,
                    item.get("role"),
                    source,
                    item.get("confidence"),
                    item.get("evidence_url"),
                    item.get("score"),
                    verified_by,
                ),
            ).fetchone()
            if row:
                saved.append(dict(row))
        conn.commit()
    return saved


def search_mbs_by_website(q: str, limit: int = 200) -> list[str]:
    like = f"%{(q or '').strip()}%"
    if like == "%%":
        return []
    with get_crm_conn() as conn:
        rows = conn.execute(
            """
            SELECT DISTINCT mbs FROM company_websites
            WHERE website ILIKE %s
            LIMIT %s
            """,
            (like, limit),
        ).fetchall()
    return [r["mbs"] for r in rows]


def get_active_job() -> dict[str, Any] | None:
    with get_crm_conn() as conn:
        row = conn.execute(
            """
            SELECT * FROM web_finder_jobs
            WHERE status IN ('queued', 'running', 'paused')
            ORDER BY id DESC
            LIMIT 1
            """
        ).fetchone()
    return dict(row) if row else None


def get_latest_jobs(limit: int = 5) -> list[dict[str, Any]]:
    with get_crm_conn() as conn:
        rows = conn.execute(
            """
            SELECT * FROM web_finder_jobs
            ORDER BY id DESC
            LIMIT %s
            """,
            (limit,),
        ).fetchall()
    return [dict(r) for r in rows]


def create_web_finder_job(
    *,
    started_by: str | None = None,
    only_with_email: bool = True,
    max_companies: int | None = 500,
    auto_save_min_score: int = 60,
    sleep_seconds: float = 4.0,
) -> dict[str, Any]:
    with get_crm_conn() as conn:
        active = conn.execute(
            """
            SELECT id, status FROM web_finder_jobs
            WHERE status IN ('queued', 'running')
            ORDER BY id DESC LIMIT 1
            """
        ).fetchone()
        if active:
            raise RuntimeError(
                f"Već postoji aktivan posao #{active['id']} ({active['status']}). "
                "Prvo pauziraj ili pričekaj završetak."
            )
        row = conn.execute(
            """
            INSERT INTO web_finder_jobs (
              status, started_by, only_with_email, max_companies,
              auto_save_min_score, sleep_seconds, last_message
            ) VALUES (
              'queued', %s, %s, %s, %s, %s, 'Čeka VPS worker…'
            )
            RETURNING *
            """,
            (
                started_by,
                only_with_email,
                max_companies,
                auto_save_min_score,
                sleep_seconds,
            ),
        ).fetchone()
        conn.commit()
    return dict(row)


def set_job_status(job_id: int, status: str, message: str | None = None) -> dict[str, Any] | None:
    with get_crm_conn() as conn:
        row = conn.execute(
            """
            UPDATE web_finder_jobs
            SET status = %s,
                last_message = COALESCE(%s, last_message),
                updated_at = NOW(),
                finished_at = CASE
                  WHEN %s IN ('done', 'failed') THEN COALESCE(finished_at, NOW())
                  WHEN %s IN ('queued', 'running', 'paused') THEN NULL
                  ELSE finished_at
                END
            WHERE id = %s
            RETURNING *
            """,
            (status, message, status, status, job_id),
        ).fetchone()
        conn.commit()
    return dict(row) if row else None


def job_stats() -> dict[str, Any]:
    with get_crm_conn() as conn:
        domains = conn.execute("SELECT count(*)::int AS n FROM company_websites").fetchone()["n"]
        companies = conn.execute(
            "SELECT count(DISTINCT mbs)::int AS n FROM company_websites"
        ).fetchone()["n"]
        attempts = conn.execute("SELECT count(*)::int AS n FROM web_finder_attempts").fetchone()["n"]
        saved = conn.execute(
            "SELECT count(*)::int AS n FROM web_finder_attempts WHERE status = 'saved'"
        ).fetchone()["n"]
    return {
        "crm_websites": domains,
        "crm_companies_with_web": companies,
        "attempts": attempts,
        "attempts_saved": saved,
    }
