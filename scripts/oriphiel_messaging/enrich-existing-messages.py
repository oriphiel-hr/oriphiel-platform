#!/usr/bin/env python3
"""
Popuni AI polja za postojeće poruke u bazi (bez IMAP-a).

  cd /root/oriphiel-ai/oriphiel_messaging
  ACCOUNT_EMAIL=mario.vitt@oriphiel.hr ONLY_MISSING=1 python3 -u enrich-existing-messages.py

Env: ACCOUNT_EMAIL, LIMIT, ONLY_MISSING, BATCH_SIZE, BATCH_SLEEP_SEC,
     OLLAMA_URL, OLLAMA_MODEL, STATUS_FILE, PG_*
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

os.environ.setdefault("RUN_AI", "1")
import importlib.util

_here = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location(
    "ollama_enrich_message", _here / "ollama-enrich-message.py"
)
mod = importlib.util.module_from_spec(_spec)
assert _spec and _spec.loader
_spec.loader.exec_module(mod)


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def env_int(name: str, default: int = 0) -> int:
    try:
        return int(env(name, str(default)) or default)
    except ValueError:
        return default


def sql_quote(s: str) -> str:
    return "'" + (s or "").replace("'", "''") + "'"


def psql(sql: str) -> str:
    container = env("PG_CONTAINER", "oriphiel-postgres")
    user = env("PG_USER", "oriphiel")
    db = env("PG_DB", "oriphiel")
    p = subprocess.run(
        [
            "docker",
            "exec",
            "-i",
            container,
            "psql",
            "-U",
            user,
            "-d",
            db,
            "-v",
            "ON_ERROR_STOP=1",
            "-At",
        ],
        input=sql.encode("utf-8"),
        capture_output=True,
    )
    if p.returncode != 0:
        err = (p.stderr or p.stdout).decode("utf-8", errors="replace")
        raise RuntimeError(err)
    return (p.stdout or b"").decode("utf-8", errors="replace").strip()


def write_status(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def fetch_ids(account: str, only_missing: bool, limit: int) -> list[int]:
    where = f"lower(ca.address) = lower({sql_quote(account)})"
    if only_missing:
        where += " AND (m.ai_summary IS NULL OR btrim(m.ai_summary) = '')"
    lim = f"LIMIT {limit}" if limit > 0 else ""
    out = psql(
        f"""
SELECT m.id
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE {where}
ORDER BY m.id
{lim};
"""
    )
    ids: list[int] = []
    for ln in out.splitlines():
        ln = ln.strip()
        if ln.isdigit():
            ids.append(int(ln))
    return ids


def fetch_message(mid: int) -> dict:
    raw = psql(
        f"""
SELECT row_to_json(t)::text
FROM (
  SELECT
    m.id,
    coalesce(m.from_address, '') AS from_address,
    coalesce(m.subject, '') AS subject,
    left(coalesce(m.body_text, ''), 6000) AS body_text
  FROM messages m
  WHERE m.id = {mid}
) t;
"""
    )
    if not raw:
        raise RuntimeError(f"poruka id={mid} nije u bazi")
    # psql may wrap long lines; take first JSON object
    raw = raw.strip()
    if not raw.startswith("{"):
        # multiline json unlikely with -At single row
        raw = "{" + raw.split("{", 1)[-1]
    return json.loads(raw)


def main() -> int:
    account = env("ACCOUNT_EMAIL", "mario.vitt@oriphiel.hr")
    limit = env_int("LIMIT", 0)
    only_missing = env("ONLY_MISSING", "1") in ("1", "true", "TRUE", "yes")
    batch = max(1, env_int("BATCH_SIZE", 20))
    sleep_sec = env_int("BATCH_SLEEP_SEC", 1)
    status_file = Path(env("STATUS_FILE", "/tmp/oriphiel-ai-enrich-mario.vitt.json"))
    log_errors = Path("/tmp/oriphiel-ai-enrich-errors.log")
    started = time.time()

    print("=== Ollama smoke test ===", flush=True)
    try:
        # samo dostupnost API-ja + model (kratki prompt ne mora dati bogat summary)
        url = env("OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")
        model = env("OLLAMA_MODEL", "llama3.1:8b")
        import urllib.request

        with urllib.request.urlopen(f"{url}/api/tags", timeout=15) as resp:
            tags = json.loads(resp.read().decode("utf-8", errors="replace"))
        names = [m.get("name") for m in (tags.get("models") or [])]
        print(f"Ollama OK models={names[:8]}", flush=True)
        if names and model not in names and not any(model in (n or "") for n in names):
            print(f"WARN: model {model!r} nije u listi — postavi OLLAMA_MODEL=...", flush=True)
        # lagani generate da model stvarno odgovori
        probe = mod.enrich_message(
            "klijent@firma.hr",
            "Upit za ponudu — ugostiteljstvo",
            "Poštovani, zanima nas eKonobar POS za kafić s 8 stolova. Molimo ponudu i rok implementacije.",
        )
        print(
            f"Probe OK priority={probe.get('ai_priority')} "
            f"summary={str(probe.get('ai_summary') or '')[:60]!r}",
            flush=True,
        )
    except Exception as exc:
        print(f"Ollama test FAIL: {exc}", file=sys.stderr)
        print("curl -s http://127.0.0.1:11434/api/tags", file=sys.stderr)
        print(f"OLLAMA_MODEL={env('OLLAMA_MODEL', 'llama3.1:8b')}", file=sys.stderr)
        return 2

    ids = fetch_ids(account, only_missing, limit)
    total = len(ids)
    print(
        f"=== AI enrich account={account} total={total} only_missing={int(only_missing)} ===",
        flush=True,
    )
    if total == 0:
        write_status(status_file, {"state": "finished", "total": 0, "ok": 0, "err": 0})
        print("Nema poruka za AI.", flush=True)
        return 0

    open(log_errors, "w", encoding="utf-8").write("")
    ok = err = skip = 0
    last_err = ""

    for i, mid in enumerate(ids, start=1):
        try:
            msg = fetch_message(mid)
            from_addr = msg.get("from_address") or ""
            subject = msg.get("subject") or ""
            body = msg.get("body_text") or ""
            if not subject.strip() and not body.strip():
                skip += 1
                continue

            ai = mod.enrich_message(from_addr, subject, body)
            if (not ai.get("ai_summary") or ai.get("ai_summary") == "(nema sažetka)") and subject.strip():
                ai["ai_summary"] = f"Predmet: {subject.strip()[:300]}"
            sets = []
            if ai.get("ai_summary"):
                sets.append(f"ai_summary = {sql_quote(ai['ai_summary'])}")
            if ai.get("ai_priority"):
                sets.append(f"ai_priority = {sql_quote(ai['ai_priority'])}")
            if ai.get("ai_draft"):
                sets.append(f"ai_draft = {sql_quote(ai['ai_draft'])}")
            if not sets:
                raise RuntimeError("Ollama vratio prazna polja")
            psql(f"UPDATE messages SET {', '.join(sets)} WHERE id = {mid};")
            ok += 1
        except Exception as exc:
            err += 1
            last_err = f"id={mid}: {exc}"
            print(f"ERR {last_err}", flush=True)
            with open(log_errors, "a", encoding="utf-8") as fh:
                fh.write(last_err + "\n")

        if i == 1 or i == total or i % batch == 0:
            print(f"PROGRESS {i}/{total} ok={ok} err={err} skip={skip}", flush=True)
            write_status(
                status_file,
                {
                    "state": "running",
                    "account_email": account,
                    "current": i,
                    "total": total,
                    "progress": f"{i}/{total}",
                    "ok": ok,
                    "err": err,
                    "skip": skip,
                    "last_error": last_err,
                    "elapsed_sec": round(time.time() - started, 1),
                },
            )
            if sleep_sec > 0:
                time.sleep(sleep_sec)

    write_status(
        status_file,
        {
            "state": "finished",
            "account_email": account,
            "total": total,
            "done": total,
            "ok": ok,
            "err": err,
            "skip": skip,
            "last_error": last_err,
            "errors_log": str(log_errors),
            "elapsed_sec": round(time.time() - started, 1),
        },
    )
    print(f"=== FINISHED ok={ok} err={err} skip={skip} ===", flush=True)
    print(f"Greške: {log_errors}", flush=True)
    return 0 if err == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
