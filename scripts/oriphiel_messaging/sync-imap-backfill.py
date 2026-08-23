#!/usr/bin/env python3
"""
Jednokratni / batch IMAP backfill -> Postgres (baza oriphiel).
Poruke + attachmenti na disk.

Env (obavezno):
  IMAP_USER, IMAP_PASSWORD
Opcionalno:
  IMAP_HOST=imap.hostinger.com  IMAP_PORT=993
  MAILBOX=INBOX
  ACCOUNT_EMAIL=mario.vitt@oriphiel.hr
  PG_CONTAINER=oriphiel-postgres  PG_USER=oriphiel  PG_DB=oriphiel
  LIMIT=0
  ONLY_UNSEEN=0
  DRY_RUN=0
  RESET_BEFORE=0
  RESET_ACCOUNTS=0
  SAVE_ATTACHMENTS=1
  ATTACH_DIR=/var/lib/oriphiel/attachments
  BATCH_SIZE=50                 # pauza + gc svakih N poruka (0 = bez pauze)
  BATCH_SLEEP_SEC=1
  RUN_AI=0                      # Ollama: ai_summary, ai_priority, ai_draft
  OLLAMA_URL=http://127.0.0.1:11434
  OLLAMA_MODEL=llama3.1:8b
  MARK_AS_SEEN=0                # IMAP \\Seen — default OFF (vidi UPUTE)
  STATUS_FILE=/tmp/oriphiel-imap-backfill-status.json
  PROGRESS_EVERY=10
"""

from __future__ import annotations

import gc
import importlib.util
import email
import email.header
import email.utils
import hashlib
import imaplib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from email.message import Message
from pathlib import Path
from typing import Any, Optional


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def env_int(name: str, default: int = 0) -> int:
    raw = env(name, str(default))
    try:
        return int(raw)
    except ValueError:
        return default


def write_status(path: Path, data: dict[str, Any]) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        tmp.replace(path)
    except Exception as exc:
        print(f"status write failed: {exc}", file=sys.stderr)


def truthy(name: str, default: str = "0") -> bool:
    return env(name, default) in ("1", "true", "TRUE", "yes", "YES")


def decode_hdr(value: Optional[str]) -> str:
    if not value:
        return ""
    parts = email.header.decode_header(value)
    out = []
    for chunk, charset in parts:
        if isinstance(chunk, bytes):
            out.append(chunk.decode(charset or "utf-8", errors="replace"))
        else:
            out.append(chunk)
    return "".join(out)


def extract_addr(value: Optional[str]) -> str:
    if not value:
        return ""
    name, addr = email.utils.parseaddr(decode_hdr(value))
    return (addr or "").strip().lower()


def sql_quote(value: Optional[str]) -> str:
    if value is None:
        return "NULL"
    tag = "b"
    body = str(value)
    while f"${tag}$" in body:
        tag += "x"
    return f"${tag}${body}${tag}$"


def strip_wrapping_quotes(value: str) -> str:
    v = value.strip()
    if len(v) >= 2 and ((v[0] == v[-1] == "'") or (v[0] == v[-1] == '"')):
        return v[1:-1]
    return v


def psql(sql: str) -> str:
    container = env("PG_CONTAINER", "oriphiel-postgres")
    user = env("PG_USER", "oriphiel")
    db = env("PG_DB", "oriphiel")
    cmd = [
        "docker", "exec", "-i", container,
        "psql", "-U", user, "-d", db,
        "-v", "ON_ERROR_STOP=1",
        "-t", "-A",
    ]
    p = subprocess.run(cmd, input=sql.encode("utf-8"), capture_output=True)
    if p.returncode != 0:
        err = (p.stderr or p.stdout).decode("utf-8", errors="replace")
        raise RuntimeError(f"psql failed:\n{err}\nSQL:\n{sql[:500]}")
    return (p.stdout or b"").decode("utf-8", errors="replace").strip()


def extract_angle_ids(value: Optional[str]) -> list[str]:
    if not value:
        return []
    return [m.group(1).strip().lower() for m in re.finditer(r"<([^>]+)>", decode_hdr(value))]


def compute_thread_key(msg: Message, uid: str, message_id_hdr: str) -> str:
    """thread_key iz In-Reply-To / References / Message-ID (RFC threading)."""
    refs = extract_angle_ids(msg.get("References"))
    in_reply = extract_angle_ids(msg.get("In-Reply-To"))
    if in_reply:
        return in_reply[0]
    if refs:
        return refs[0]
    mids = extract_angle_ids(message_id_hdr)
    if mids:
        return mids[0]
    return f"uid-{uid}"


def load_ollama_enricher():
    here = Path(__file__).resolve().parent
    mod_path = here / "ollama-enrich-message.py"
    spec = importlib.util.spec_from_file_location("ollama_enrich_message", mod_path)
    if not spec or not spec.loader:
        return None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def update_message_fields(
    message_db_id: int,
    *,
    thread_key: str,
    ai_summary: Optional[str] = None,
    ai_priority: Optional[str] = None,
    ai_draft: Optional[str] = None,
) -> None:
    sets = [f"thread_key = {sql_quote(thread_key)}"]
    if ai_summary is not None:
        sets.append(f"ai_summary = {sql_quote(ai_summary)}")
    if ai_priority is not None:
        sets.append(f"ai_priority = {sql_quote(ai_priority)}")
    if ai_draft is not None:
        sets.append(f"ai_draft = {sql_quote(ai_draft)}")
    psql(f"UPDATE messages SET {', '.join(sets)} WHERE id = {message_db_id};")


def mark_imap_seen(imap: imaplib.IMAP4_SSL, uid: str, enabled: bool) -> None:
    if not enabled:
        return
    try:
        imap.store(uid.encode("ascii"), "+FLAGS", "\\Seen")
    except Exception as exc:
        print(f"  WARN mark_seen uid={uid}: {exc}", file=sys.stderr, flush=True)


def get_body(msg: Message) -> tuple[str, str]:
    text_plain = ""
    text_html = ""
    if msg.is_multipart():
        for part in msg.walk():
            ctype = (part.get_content_type() or "").lower()
            disp = str(part.get("Content-Disposition") or "").lower()
            if "attachment" in disp:
                continue
            try:
                payload = part.get_payload(decode=True) or b""
                charset = part.get_content_charset() or "utf-8"
                decoded = payload.decode(charset, errors="replace")
            except Exception:
                continue
            if ctype == "text/plain" and not text_plain:
                text_plain = decoded
            elif ctype == "text/html" and not text_html:
                text_html = decoded
    else:
        try:
            payload = msg.get_payload(decode=True) or b""
            charset = msg.get_content_charset() or "utf-8"
            decoded = payload.decode(charset, errors="replace")
            if (msg.get_content_type() or "").lower() == "text/html":
                text_html = decoded
            else:
                text_plain = decoded
        except Exception:
            pass
    return text_plain, text_html


def safe_filename(name: str) -> str:
    name = decode_hdr(name) if name else "attachment.bin"
    name = name.replace("\\", "_").replace("/", "_").replace("\x00", "")
    name = re.sub(r"[^\w.\- ()\[\]]+", "_", name, flags=re.UNICODE).strip(" ._")
    if not name:
        name = "attachment.bin"
    return name[:180]


def iter_attachments(msg: Message) -> list[dict]:
    out: list[dict] = []
    for part in msg.walk():
        if part.get_content_maintype() == "multipart":
            continue
        filename = part.get_filename()
        disp = str(part.get("Content-Disposition") or "").lower()
        ctype = part.get_content_type() or "application/octet-stream"
        is_inline = "inline" in disp and "attachment" not in disp

        if filename:
            filename = safe_filename(decode_hdr(filename))
        elif "attachment" in disp:
            filename = "attachment.bin"
        else:
            continue

        try:
            payload = part.get_payload(decode=True) or b""
        except Exception:
            continue
        if not payload:
            continue

        content_id = (part.get("Content-ID") or "").strip().strip("<>")
        digest = hashlib.sha256(payload).hexdigest()
        out.append(
            {
                "filename": filename,
                "mime_type": ctype,
                "size_bytes": len(payload),
                "payload": payload,
                "sha256": digest,
                "content_id": content_id or None,
                "is_inline": bool(is_inline),
            }
        )
    return out


def reset_account_data(account_id: int, channel: str, attach_dir: Path) -> None:
    """Delete DB rows + on-disk files for one account only."""
    print(f"RESET_BEFORE: account_id={account_id} channel={channel} (DB + files)")
    psql(
        f"""
DELETE FROM message_attachments
WHERE message_id IN (SELECT id FROM messages WHERE account_id = {account_id});
DELETE FROM messages WHERE account_id = {account_id};
"""
    )
    # new layout: {channel}/{account_id}
    dirs = [
        attach_dir / channel / str(account_id),
        attach_dir / str(account_id),  # old layout cleanup
    ]
    for account_dir in dirs:
        if account_dir.exists():
            shutil.rmtree(account_dir)
            print(f"RESET_BEFORE: removed {account_dir}")
    new_dir = attach_dir / channel / str(account_id)
    new_dir.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(new_dir, 0o775)
    except Exception:
        pass


def reset_messaging_tables(include_accounts: bool = False) -> None:
    # Kept for emergency full wipe via RESET_ALL=1
    if include_accounts:
        sql = """
TRUNCATE TABLE
  message_attachments,
  messages,
  contacts,
  channels_accounts
RESTART IDENTITY CASCADE;
"""
        print("RESET_ALL: truncate attachments, messages, contacts, channels_accounts")
    else:
        sql = """
TRUNCATE TABLE
  message_attachments,
  messages,
  contacts
RESTART IDENTITY CASCADE;
"""
        print("RESET_ALL: truncate attachments, messages, contacts (accounts stay)")
    psql(sql)


def ensure_account(account_email: str) -> int:
    row = psql(
        f"SELECT id FROM channels_accounts WHERE lower(address) = lower({sql_quote(account_email)}) LIMIT 1;"
    )
    if row:
        return int(row.splitlines()[0])
    key = "email_" + re.sub(r"[^a-z0-9]+", "_", account_email.lower()).strip("_")
    row = psql(
        f"""
INSERT INTO channels_accounts (name, account_key, channel, address, provider)
VALUES ({sql_quote(account_email)}, {sql_quote(key)}, 'email', {sql_quote(account_email)}, 'imap')
ON CONFLICT (account_key) DO UPDATE SET address = EXCLUDED.address, is_active = TRUE
RETURNING id;
"""
    )
    return int(row.splitlines()[0])


def upsert_contact(from_email: str) -> Optional[int]:
    if not from_email:
        return None
    psql(
        f"""
INSERT INTO contacts (primary_email)
SELECT lower({sql_quote(from_email)})
WHERE NOT EXISTS (
  SELECT 1 FROM contacts WHERE primary_email = lower({sql_quote(from_email)})
);
"""
    )
    row = psql(
        f"SELECT id FROM contacts WHERE primary_email = lower({sql_quote(from_email)}) LIMIT 1;"
    )
    if not row:
        return None
    return int(row.splitlines()[0])


def insert_message(
    account_id: int,
    contact_id: Optional[int],
    from_addr: str,
    subject: str,
    body_text: str,
    body_html: str,
    external_id: str,
    thread_key: str,
    received_at: Optional[str],
) -> Optional[int]:
    contact_sql = "NULL" if contact_id is None else str(contact_id)
    received_sql = "NULL" if not received_at else f"{sql_quote(received_at)}::timestamptz"
    ret = psql(
        f"""
INSERT INTO messages (
  account_id, contact_id, channel, direction,
  from_address, subject, body_text, body_html,
  external_id, thread_key, status, received_at
) VALUES (
  {account_id}, {contact_sql}, 'email', 'in',
  {sql_quote(from_addr)}, {sql_quote(subject)}, {sql_quote(body_text)}, {sql_quote(body_html)},
  {sql_quote(external_id)}, {sql_quote(thread_key)}, 'new', {received_sql}
)
ON CONFLICT (channel, external_id) DO UPDATE SET
  subject = EXCLUDED.subject,
  body_text = EXCLUDED.body_text,
  body_html = EXCLUDED.body_html,
  from_address = EXCLUDED.from_address,
  thread_key = EXCLUDED.thread_key,
  received_at = EXCLUDED.received_at
RETURNING id;
"""
    )
    if ret:
        return int(ret.splitlines()[0])
    row = psql(
        f"SELECT id FROM messages WHERE channel = 'email' AND external_id = {sql_quote(external_id)} LIMIT 1;"
    )
    if row:
        return int(row.splitlines()[0])
    return None


def insert_attachment_row(
    message_db_id: int,
    fname: str,
    mime_type: str,
    size_bytes: int,
    storage_path: str,
    sha256: str,
    content_id: Optional[str],
    is_inline: bool,
) -> None:
    exists = psql(
        f"""
SELECT id FROM message_attachments
WHERE message_id = {message_db_id} AND sha256 = {sql_quote(sha256)}
LIMIT 1;
"""
    )
    if exists:
        return
    cid = "NULL" if not content_id else sql_quote(content_id)
    inline = "TRUE" if is_inline else "FALSE"
    psql(
        f"""
INSERT INTO message_attachments (
  message_id, filename, mime_type, size_bytes, storage_path, sha256, content_id, is_inline
) VALUES (
  {message_db_id},
  {sql_quote(fname)},
  {sql_quote(mime_type)},
  {size_bytes},
  {sql_quote(storage_path)},
  {sql_quote(sha256)},
  {cid},
  {inline}
);
"""
    )


def save_attachments_fixed(
    message_db_id: int,
    account_id: int,
    channel: str,
    attachments: list[dict],
    attach_dir: Path,
    url_prefix: str,
    max_bytes: int,
    dry_run: bool,
) -> int:
    if not attachments:
        return 0
    channel = (channel or "email").strip().lower() or "email"
    account_dir = attach_dir / channel / str(account_id)
    account_dir.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(account_dir, 0o775)
    except Exception:
        pass

    saved = 0
    for i, att in enumerate(attachments):
        if att["size_bytes"] > max_bytes:
            print(
                f"  skip attach too large: {att['filename']} ({att['size_bytes']} bytes)",
                file=sys.stderr,
            )
            continue
        fname = att["filename"]
        disk_name = f"{message_db_id}_{i}_{fname}"
        host_path = account_dir / disk_name
        storage_path = str(host_path)
        if dry_run:
            print(f"  DRY attach {fname} -> {storage_path} ({att['size_bytes']} B)")
            saved += 1
            continue
        host_path.write_bytes(att["payload"])
        try:
            os.chmod(host_path, 0o644)
        except Exception:
            pass
        insert_attachment_row(
            message_db_id=message_db_id,
            fname=fname,
            mime_type=att["mime_type"],
            size_bytes=att["size_bytes"],
            storage_path=storage_path,
            sha256=att["sha256"],
            content_id=att["content_id"],
            is_inline=att["is_inline"],
        )
        saved += 1
        print(f"  ATTACH {fname} -> {storage_path}")
    return saved


def main() -> int:
    imap_host = env("IMAP_HOST", "imap.hostinger.com")
    imap_port = env_int("IMAP_PORT", 993)
    imap_user = env("IMAP_USER")
    imap_pass = strip_wrapping_quotes(env("IMAP_PASSWORD"))
    mailbox = env("MAILBOX", "INBOX")
    account_email = env("ACCOUNT_EMAIL", imap_user)
    limit = env_int("LIMIT", 0)
    only_unseen = truthy("ONLY_UNSEEN")
    dry_run = truthy("DRY_RUN")
    reset_before = truthy("RESET_BEFORE")
    reset_all = truthy("RESET_ALL")
    reset_accounts = truthy("RESET_ACCOUNTS")
    save_attachments = truthy("SAVE_ATTACHMENTS", "1")
    attach_dir = Path(env("ATTACH_DIR", "/var/lib/oriphiel/attachments"))
    url_prefix = env("ATTACH_URL_PREFIX", "/data/attachments")
    max_attach = env_int("MAX_ATTACH_BYTES", 25 * 1024 * 1024)
    status_file = Path(env("STATUS_FILE", "/tmp/oriphiel-imap-backfill-status.json"))
    progress_every = max(1, env_int("PROGRESS_EVERY", 10))
    batch_size = env_int("BATCH_SIZE", 50)
    batch_sleep = env_int("BATCH_SLEEP_SEC", 1)
    run_ai = truthy("RUN_AI", "0")
    mark_as_seen = truthy("MARK_AS_SEEN", "0")
    ollama = load_ollama_enricher() if run_ai else None
    started_at = time.time()

    if not imap_user or not imap_pass:
        print("Set IMAP_USER and IMAP_PASSWORD", file=sys.stderr)
        return 2

    print(f"=== STARTED backfill account={account_email} ===", flush=True)
    print(f"IMAP {imap_host}:{imap_port} user={imap_user} mailbox={mailbox}", flush=True)
    print(f"SAVE_ATTACHMENTS={int(save_attachments)} ATTACH_DIR={attach_dir}/{{channel}}/{{account_id}}", flush=True)
    print(
        f"BATCH_SIZE={batch_size} RUN_AI={int(run_ai)} MARK_AS_SEEN={int(mark_as_seen)} "
        f"(Seen=IMAP flag, ne znaci da si osobno procitao)",
        flush=True,
    )
    print(f"STATUS_FILE={status_file} PROGRESS_EVERY={progress_every}", flush=True)
    account_id = ensure_account(account_email)
    channel = "email"
    print(f"account_id={account_id} channel={channel}", flush=True)
    print(f"attach_path_example={attach_dir / channel / str(account_id)}", flush=True)

    write_status(
        status_file,
        {
            "state": "starting",
            "account_email": account_email,
            "account_id": account_id,
            "current": 0,
            "total": 0,
            "progress": "0/0",
            "messages_processed": 0,
            "attachments_saved": 0,
            "errors": 0,
            "started_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        },
    )

    if reset_all and not dry_run:
        reset_messaging_tables(include_accounts=reset_accounts)
        # wipe all attachment files
        if attach_dir.exists():
            for child in attach_dir.iterdir():
                if child.is_dir():
                    shutil.rmtree(child)
                else:
                    child.unlink(missing_ok=True)
            print(f"RESET_ALL: cleared files under {attach_dir}")
    elif reset_before and not dry_run:
        reset_account_data(account_id=account_id, channel=channel, attach_dir=attach_dir)
    elif (reset_before or reset_all) and dry_run:
        print("RESET skipped (DRY_RUN=1)")

    M = imaplib.IMAP4_SSL(imap_host, imap_port)
    M.login(imap_user, imap_pass)
    typ, _ = M.select(mailbox, readonly=not mark_as_seen)
    if typ != "OK":
        print(f"Cannot select mailbox {mailbox}", file=sys.stderr)
        return 1

    criteria = "UNSEEN" if only_unseen else "ALL"
    typ, data = M.search(None, criteria)
    if typ != "OK":
        print("IMAP search failed", file=sys.stderr)
        return 1

    ids = (data[0] or b"").split()
    if limit > 0:
        ids = ids[-limit:]

    total = len(ids)
    print(f"Found {total} messages (criteria={criteria}, limit={limit or 'all'})", flush=True)
    print(f"PROGRESS 0/{total}", flush=True)
    if total == 0:
        print("Nothing to do (0 messages).", flush=True)
    inserted = 0
    skipped = 0
    errors = 0
    attach_count = 0

    write_status(
        status_file,
        {
            "state": "running",
            "account_email": account_email,
            "account_id": account_id,
            "current": 0,
            "total": total,
            "progress": f"0/{total}",
            "messages_processed": 0,
            "attachments_saved": 0,
            "errors": 0,
            "started_at": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(started_at)),
        },
    )

    for idx, raw_id in enumerate(ids, start=1):
        uid = raw_id.decode("ascii", errors="ignore")
        subject_short = ""
        try:
            typ, msg_data = M.fetch(raw_id, "(RFC822)")
            if typ != "OK" or not msg_data or not msg_data[0]:
                errors += 1
                continue
            raw_email = msg_data[0][1]
            msg = email.message_from_bytes(raw_email)

            from_addr = extract_addr(msg.get("From"))
            subject = decode_hdr(msg.get("Subject"))
            subject_short = subject[:50]
            message_id = (msg.get("Message-ID") or "").strip()
            date_hdr = msg.get("Date")
            received_at = None
            if date_hdr:
                try:
                    received_at = email.utils.parsedate_to_datetime(date_hdr).isoformat()
                except Exception:
                    received_at = None

            body_text, body_html = get_body(msg)
            attachments = iter_attachments(msg) if save_attachments else []
            thread_key = compute_thread_key(msg, uid, message_id)
            external_id = f"uid-{uid}"
            if message_id:
                external_id = f"mid-{message_id}"

            if dry_run:
                print(
                    f"DRY uid={uid} thread={thread_key[:40]!r} from={from_addr} "
                    f"subject={subject[:60]!r} attaches={len(attachments)}",
                    flush=True,
                )
                if save_attachments and attachments:
                    save_attachments_fixed(
                        message_db_id=0,
                        account_id=account_id,
                        channel=channel,
                        attachments=attachments,
                        attach_dir=attach_dir,
                        url_prefix=url_prefix,
                        max_bytes=max_attach,
                        dry_run=True,
                    )
                inserted += 1
            else:
                contact_id = upsert_contact(from_addr) if from_addr else None
                msg_db_id = insert_message(
                    account_id=account_id,
                    contact_id=contact_id,
                    from_addr=from_addr,
                    subject=subject,
                    body_text=body_text,
                    body_html=body_html,
                    external_id=external_id,
                    thread_key=thread_key,
                    received_at=received_at,
                )
                if msg_db_id is None:
                    errors += 1
                else:
                    ai_summary = ai_priority = ai_draft = None
                    if ollama and (body_text or subject):
                        ai = ollama.enrich_if_enabled(from_addr, subject, body_text)
                        if ai:
                            ai_summary = ai.get("ai_summary")
                            ai_priority = ai.get("ai_priority")
                            ai_draft = ai.get("ai_draft")
                    if ai_summary or ai_priority or ai_draft:
                        update_message_fields(
                            msg_db_id,
                            thread_key=thread_key,
                            ai_summary=ai_summary,
                            ai_priority=ai_priority,
                            ai_draft=ai_draft,
                        )
                    if save_attachments and attachments:
                        n = save_attachments_fixed(
                            message_db_id=msg_db_id,
                            account_id=account_id,
                            channel=channel,
                            attachments=attachments,
                            attach_dir=attach_dir,
                            url_prefix=url_prefix,
                            max_bytes=max_attach,
                            dry_run=False,
                        )
                        attach_count += n
                    mark_imap_seen(M, uid, mark_as_seen)
                    inserted += 1
        except Exception as exc:
            errors += 1
            print(f"ERR uid={uid}: {exc}", file=sys.stderr, flush=True)
        finally:
            if batch_size > 0 and idx % batch_size == 0:
                print(f"BATCH {idx}/{total} — pauza {batch_sleep}s", flush=True)
                gc.collect()
                if batch_sleep > 0:
                    time.sleep(batch_sleep)
            show = idx == 1 or idx == total or idx % progress_every == 0
            if show:
                print(
                    f"PROGRESS {idx}/{total} processed={inserted} attachments={attach_count} "
                    f"errors={errors} subject={subject_short!r}",
                    flush=True,
                )
            write_status(
                status_file,
                {
                    "state": "running",
                    "account_email": account_email,
                    "account_id": account_id,
                    "current": idx,
                    "total": total,
                    "progress": f"{idx}/{total}",
                    "messages_processed": inserted,
                    "attachments_saved": attach_count,
                    "errors": errors,
                    "last_subject": subject_short,
                    "elapsed_sec": round(time.time() - started_at, 1),
                    "started_at": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(started_at)),
                },
            )

    try:
        M.close()
    except Exception:
        pass
    M.logout()

    elapsed = round(time.time() - started_at, 1)
    print(
        f"DONE messages_processed={inserted} skipped_marker={skipped} "
        f"attachments_saved={attach_count} errors={errors} elapsed_sec={elapsed}",
        flush=True,
    )
    print(f"PROGRESS {total}/{total} DONE", flush=True)
    # Jedan red za n8n Output (lako citanje)
    result = {
        "account_email": account_email,
        "account_id": account_id,
        "total": total,
        "progress": f"{total}/{total}",
        "messages_processed": inserted,
        "attachments_saved": attach_count,
        "errors": errors,
        "elapsed_sec": elapsed,
        "dry_run": dry_run,
        "reset_before": reset_before,
        "state": "finished",
    }
    print("RESULT " + json.dumps(result, ensure_ascii=False), flush=True)
    write_status(status_file, result)
    print(f"=== FINISHED {inserted}/{total} (errors={errors}) ===", flush=True)
    return 0 if errors == 0 else 1


if __name__ == "__main__":
    # line-buffered stdout so n8n/SSH sees PROGRESS live when supported
    try:
        sys.stdout.reconfigure(line_buffering=True)  # type: ignore[attr-defined]
    except Exception:
        pass
    sys.exit(main())
