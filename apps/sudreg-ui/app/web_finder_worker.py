"""Pozadinski worker: traži web za tvrtke bez CRM zapisa.

Pokretanje (VPS / docker):
  python -m app.web_finder_worker

Čita poslove iz oriphiel_crm.web_finder_jobs (status queued/running).
Laptop može biti ugašen — radi samo VPS proces.
"""

from __future__ import annotations

import logging
import signal
import time
from datetime import datetime, timezone
from typing import Any

from . import crm
from . import db
from . import website_finder
from .config import settings

log = logging.getLogger("web_finder_worker")

_stop = False


def _handle_sig(*_args: Any) -> None:
    global _stop
    _stop = True
    log.info("Stop signal — završavam nakon trenutne tvrtke")


def _now() -> datetime:
    return datetime.now(timezone.utc)


def claim_job() -> dict[str, Any] | None:
    with crm.get_crm_conn() as conn:
        row = conn.execute(
            """
            SELECT * FROM web_finder_jobs
            WHERE status IN ('queued', 'running')
            ORDER BY
              CASE WHEN status = 'running' THEN 0 ELSE 1 END,
              id ASC
            LIMIT 1
            FOR UPDATE SKIP LOCKED
            """
        ).fetchone()
        if not row:
            conn.commit()
            return None
        job = dict(row)
        if job["status"] == "queued":
            conn.execute(
                """
                UPDATE web_finder_jobs
                SET status = 'running',
                    started_at = COALESCE(started_at, NOW()),
                    updated_at = NOW(),
                    last_message = 'Worker preuzeo posao'
                WHERE id = %s
                """,
                (job["id"],),
            )
            job["status"] = "running"
        conn.commit()
        return job


def refresh_job(job_id: int) -> dict[str, Any] | None:
    with crm.get_crm_conn() as conn:
        row = conn.execute(
            "SELECT * FROM web_finder_jobs WHERE id = %s", (job_id,)
        ).fetchone()
    return dict(row) if row else None


def update_job(job_id: int, **fields: Any) -> None:
    if not fields:
        return
    cols = []
    vals: list[Any] = []
    for k, v in fields.items():
        cols.append(f"{k} = %s")
        vals.append(v)
    cols.append("updated_at = NOW()")
    vals.append(job_id)
    with crm.get_crm_conn() as conn:
        conn.execute(
            f"UPDATE web_finder_jobs SET {', '.join(cols)} WHERE id = %s",
            vals,
        )
        conn.commit()


def record_attempt(
    *,
    mbs: str,
    oib: str | None,
    status: str,
    website: str | None = None,
    score: int | None = None,
    confidence: str | None = None,
    detail: str | None = None,
    job_id: int | None = None,
) -> None:
    with crm.get_crm_conn() as conn:
        conn.execute(
            """
            INSERT INTO web_finder_attempts (
              mbs, oib, status, website, score, confidence, detail, job_id, attempted_at
            ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,NOW())
            ON CONFLICT (mbs) DO UPDATE SET
              oib = EXCLUDED.oib,
              status = EXCLUDED.status,
              website = EXCLUDED.website,
              score = EXCLUDED.score,
              confidence = EXCLUDED.confidence,
              detail = EXCLUDED.detail,
              job_id = EXCLUDED.job_id,
              attempted_at = NOW()
            """,
            (mbs, oib, status, website, score, confidence, detail, job_id),
        )
        conn.commit()


def fetch_candidates(
    *,
    limit: int,
    only_with_email: bool,
    retry_after_days: int = 14,
) -> list[dict[str, Any]]:
    """Tvrtke iz sudreg bez CRM weba i bez svježeg attempta."""
    have = set()
    with crm.get_crm_conn() as conn:
        for r in conn.execute("SELECT mbs FROM company_websites").fetchall():
            have.add(r["mbs"])
        recent = conn.execute(
            """
            SELECT mbs FROM web_finder_attempts
            WHERE attempted_at > NOW() - (%s || ' days')::interval
            """,
            (str(retry_after_days),),
        ).fetchall()
        skip = have | {r["mbs"] for r in recent}

    # Uzmi više pa filtriraj u Pythonu (jednostavno, bez temp tablica)
    email_clause = "AND c.email IS NOT NULL AND btrim(c.email) <> ''" if only_with_email else ""
    sql = f"""
      SELECT c.mbs, c.oib, c.naziv, c.naziv_kraci, c.email, c.adresa
      FROM companies c
      WHERE NOT c.deleted
        {email_clause}
      ORDER BY c.fetched_at DESC NULLS LAST, c.mbs
      LIMIT %s
    """
    with db.get_conn() as conn:
        # uzmi buffer
        rows = conn.execute(sql, (max(limit * 8, 200),)).fetchall()

    out: list[dict[str, Any]] = []
    for r in rows:
        if r["mbs"] in skip:
            continue
        out.append(dict(r))
        if len(out) >= limit:
            break
    return out


def process_one(company: dict[str, Any], job: dict[str, Any]) -> str:
    """Vrati: saved | none | low_score | error"""
    mbs = company["mbs"]
    min_score = int(job.get("auto_save_min_score") or 60)
    try:
        find = website_finder.find_websites_for_company(company)
        results = find.get("results") or []
        if not results:
            record_attempt(
                mbs=mbs,
                oib=company.get("oib"),
                status="none",
                detail="Nema kandidata",
                job_id=job["id"],
            )
            return "none"

        ranked = website_finder.rank_results_for_company(results, company)
        qualifying = [
            r for r in ranked if int(r.get("score") or 0) >= min_score and r.get("website")
        ]
        if not qualifying:
            best = ranked[0]
            record_attempt(
                mbs=mbs,
                oib=company.get("oib"),
                status="low_score",
                website=best.get("website"),
                score=int(best.get("score") or 0),
                confidence=best.get("confidence"),
                detail=f"Ispod praga {min_score}",
                job_id=job["id"],
            )
            return "low_score"

        saved_rows = crm.save_ranked_websites(
            mbs=mbs,
            ranked=qualifying,
            oib=company.get("oib"),
            source="web_finder_batch",
            verified_by="worker",
            min_score=min_score,
        )
        primary = saved_rows[0] if saved_rows else qualifying[0]
        extra = len(saved_rows) - 1
        detail = f"Auto-spremljeno {len(saved_rows)} domena"
        if extra > 0:
            detail += f" (glavna: {primary.get('website')}, +{extra} dodatnih)"
        record_attempt(
            mbs=mbs,
            oib=company.get("oib"),
            status="saved",
            website=primary.get("website"),
            score=primary.get("score"),
            confidence=qualifying[0].get("confidence"),
            detail=detail,
            job_id=job["id"],
        )
        return "saved"
    except Exception as e:
        record_attempt(
            mbs=mbs,
            oib=company.get("oib"),
            status="error",
            detail=str(e)[:500],
            job_id=job["id"],
        )
        return "error"


def run_job(job: dict[str, Any]) -> None:
    job_id = job["id"]
    batch = 25
    sleep_s = float(job.get("sleep_seconds") or 4)
    only_email = bool(job.get("only_with_email", True))
    max_n = job.get("max_companies")

    while not _stop:
        job = refresh_job(job_id) or job
        if job["status"] == "paused":
            update_job(job_id, last_message="Pauzirano")
            return
        if job["status"] not in ("running", "queued"):
            return

        processed = int(job.get("processed") or 0)
        if max_n is not None and processed >= int(max_n):
            update_job(
                job_id,
                status="done",
                finished_at=_now(),
                last_message=f"Dosegnut limit {max_n}",
            )
            return

        remaining = batch
        if max_n is not None:
            remaining = min(batch, int(max_n) - processed)
        if remaining <= 0:
            update_job(job_id, status="done", finished_at=_now(), last_message="Gotovo")
            return

        candidates = fetch_candidates(limit=remaining, only_with_email=only_email)
        if not candidates:
            update_job(
                job_id,
                status="done",
                finished_at=_now(),
                last_message="Nema više kandidata (bez CRM weba)",
            )
            return

        for company in candidates:
            if _stop:
                update_job(job_id, status="paused", last_message="Worker zaustavljen (signal)")
                return
            job = refresh_job(job_id) or job
            if job["status"] == "paused":
                update_job(job_id, last_message="Pauzirano")
                return

            result = process_one(company, job)
            fields: dict[str, Any] = {
                "processed": int(job.get("processed") or 0) + 1,
                "last_mbs": company["mbs"],
                "last_message": f"{company.get('naziv_kraci') or company.get('naziv') or company['mbs']}: {result}",
            }
            if result == "saved":
                fields["saved"] = int(job.get("saved") or 0) + 1
            elif result == "error":
                fields["errors"] = int(job.get("errors") or 0) + 1
            else:
                fields["skipped"] = int(job.get("skipped") or 0) + 1
            update_job(job_id, **fields)
            job.update(fields)
            time.sleep(sleep_s)


def main_loop(poll_seconds: float = 5.0) -> None:
    log.info(
        "Web finder worker start (sudreg=%s crm=%s)",
        settings.database_url.split("@")[-1] if settings.database_url else "?",
        (settings.crm_database_url or "(derived)").split("@")[-1],
    )
    while not _stop:
        try:
            job = claim_job()
            if job:
                log.info("Job #%s — running", job["id"])
                try:
                    run_job(job)
                except Exception as e:
                    log.exception("Job #%s failed", job["id"])
                    update_job(
                        job["id"],
                        status="failed",
                        error_text=str(e)[:1000],
                        finished_at=_now(),
                        last_message="Greška workera",
                    )
            else:
                time.sleep(poll_seconds)
        except Exception:
            log.exception("Poll greška")
            time.sleep(poll_seconds)
    log.info("Worker izlazi")


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    signal.signal(signal.SIGINT, _handle_sig)
    signal.signal(signal.SIGTERM, _handle_sig)
    main_loop()


if __name__ == "__main__":
    main()
