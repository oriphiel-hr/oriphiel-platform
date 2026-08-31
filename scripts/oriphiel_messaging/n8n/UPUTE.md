# Oriphiel Messaging — n8n + IMAP + AI

VPS: `186.240.157.80` (`srv1890026`)  
Skripte: `/root/oriphiel-ai/oriphiel_messaging/`  
Attachmenti: `/var/lib/oriphiel/attachments/email/{account_id}/`  
Baza: Postgres `oriphiel` (container `oriphiel-postgres`)

---

## Arhitektura (Live = stub + shared process)

| Datoteka (lokalno / Downloads) | Uloga |
|--------------------------------|--------|
| **`oriphiel-live-process.json`** → `Oriphiel-Live-Process.json` | **Zajednički** pipeline (Get Account → Message → AI → Attachments). **Jednom.** |
| **`oriphiel-live-imap-stub.json`** → `Oriphiel-Live-Imap-Stub.json` | **Tanki IMAP** stub. **1× po mailboxu** → Execute Workflow → Process. |
| **`oriphiel-mail-hub.json`** → `Oriphiel-Mail-Hub.json` | **Ops** — backfill / enrich / count. **Jedan** za sve accounte. |
| `oriphiel-error-notify.json` | Error Workflow |
| `MULTI-ACCOUNT.md` | Novi mailbox |

**Deprecated:** stari monolit `oriphiel-live-account-stub.json`, `new-mails-mario-vitt.json`.

```
  [IMAP Stub × N]              [Mail Hub × 1]
   IMAP → Call Process          Account Config
            \                   ACTION=…
             \                     /
              ▼                   ▼
     [Live Process × 1]     SSH / Python
     Message → AI → Attach
              ▼
     Postgres + attachments/
```

---

## Import u n8n (redoslijed)

1. Import `oriphiel-error-notify.json` → Active  
2. Import **`Oriphiel-Live-Process.json`** → Postgres + SSH → **Active**  
3. Import **`Oriphiel-Live-Imap-Stub.json`**  
   - IMAP credential za mailbox  
   - **Account Email** = npr. `mario.vitt@oriphiel.hr`  
   - Nod **Call Live Process** → workflow `Oriphiel — Live Process (shared)`  
   - Settings → **Error Workflow** → Error notify  
   - **Active**  
4. Import `Oriphiel-Mail-Hub.json` (ops)  
5. Stari monolit / **New mails - mario…** → **Deactivate**  

Credentials: Postgres, IMAP, SSH (isti kao prije).

---

## Live (novi mail)

Tok: **Stub** IMAP → Account Email → Call Process → **Process** Get Account → Normalize → Contact → Insert Message → **AI** → Attachments

- `thread_key` iz In-Reply-To / References / Message-ID  
- Disk: `/var/lib/oriphiel/attachments/email/{account_id}/`  
- **Ne** markiraj IMAP as read  

### Novi mailbox

1. `cp accounts/*.env.example accounts/XYZ.env` na VPS-u + lozinka  
2. n8n: **Duplicate samo IMAP Stub** (ne Process) → novi IMAP + Account Email  
3. Hub: samo Account Config  

---

## Hub — ops (backfill / AI / broj)

1. Otvori **Account Config** (Code nod) — uredi `cfg` objekt na vrhu
2. Primjer backfill: `ACTION: 'backfill'`, `RESET_BEFORE: '0'`, `RUN_AI: '0'`
3. **Manual Trigger** → Execute workflow

Komentari u kodu navode dopuštene vrijednosti. Set text polja uklonjena (n8n bug → `[object Object]`).
| ACTION | Status na VPS-u |
|--------|------------------|
| `backfill` | `watch -n2 cat /tmp/oriphiel-imap-backfill-{STATUS_TAG}.json` |
| `enrich` | `watch -n5 cat /tmp/oriphiel-ai-enrich-{STATUS_TAG}.json` |
| `count` | output noda Broj mailova (`mailova`, `s_ai`, …) |

Backfill ide **nohup** (ne blokira n8n). `flock` / pgrep sprečava dva odjednom.

### AI za već ubačene mailove

`ACTION=enrich` (ne backfill s RUN_AI) — skripta `enrich-existing-messages.py`, samo poruke bez `ai_summary`.

### VPS ručno (ako treba)

```bash
cd /root/oriphiel-ai/oriphiel_messaging

# full wipe+uvoz bez AI (brzo)
ENV_FILE=accounts/oriphiel.hr-mario.vitt.env RESET_BEFORE=1 RUN_AI=0 \
  STATUS_FILE=/tmp/oriphiel-imap-backfill-mario.vitt.json \
  nohup bash sync-imap-backfill.sh >/tmp/oriphiel-imap-backfill-last.log 2>&1 &

# AI na postojećima
nohup env ACCOUNT_EMAIL=mario.vitt@oriphiel.hr ONLY_MISSING=1 \
  STATUS_FILE=/tmp/oriphiel-ai-enrich-mario.vitt.json \
  python3 -u enrich-existing-messages.py >/tmp/oriphiel-ai-enrich-last.log 2>&1 &

# svi accounti
bash sync-imap-backfill-all.sh
```

---

## Provjera baze i priloga

```powershell
powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging\Check-OriphielMessaging.ps1
```

```bash
cd /root/oriphiel-ai/oriphiel_messaging
bash check-messaging.sh
```

SQL: `sql/useful-selects.sql`

```bash
docker exec -i oriphiel-postgres psql -U oriphiel -d oriphiel -c "
SELECT count(*) AS mailova,
       count(*) FILTER (WHERE ai_summary IS NOT NULL AND btrim(ai_summary)<>'') AS s_ai
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address)='mario.vitt@oriphiel.hr';"
```

---

## Mark as read

**Default OFF** (`MARK_AS_SEEN=0`). IMAP `\Seen` ≠ da si ti pročitao mail.

---

## VPS putanje

| Što | Putanja |
|-----|---------|
| Skripte | `/root/oriphiel-ai/oriphiel_messaging/` |
| Env | `.../accounts/*.env` |
| Attachmenti | `/var/lib/oriphiel/attachments/email/{id}/` |
| n8n | `http://186.240.157.80:5678` |
| Ollama | `http://127.0.0.1:11434` |

Upload skripti s Windowsa: `Deploy-ImapBackfill.ps1`

---

## Folderi / labele / delete sync

Migracija (jednom):

```powershell
powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging\Apply-MigrateFolderLabels.ps1
```

Zatim upload novog `sync-imap-backfill.py` + `.sh` (`Deploy-ImapBackfill.ps1`).

| Env | Značenje |
|-----|----------|
| `MAILBOXES=INBOX,Sent,Archive` | Više foldera (aliasi: Sent/Archive/…) |
| `SYNC_DELETE=1` | Soft-delete kad UID nestane (`deleted_at`, `status=deleted`) |
| `ONLY_RECONCILE=1` | Samo delete + refresh FLAGS/labela (bez RFC822) |

Reconcile (brzo, cron-friendly):

```bash
ENV_FILE=accounts/oriphiel.hr-mario.vitt.env bash sync-imap-reconcile.sh
```

Full multi-folder backfill (novi `external_id` = `imap:FOLDER:uid-N`):

```bash
MAILBOXES=INBOX,Sent,Archive SYNC_DELETE=1 ENV_FILE=accounts/oriphiel.hr-mario.vitt.env \
  bash sync-imap-backfill.sh
```

**Napomena:** stari redovi (`mid-…` / `uid-…`) nemaju `folder`/`imap_uid` — delete sync vrijedi nakon novog backfilla. Live IMAP i dalje samo INBOX; labele se pune pri backfill/reconcile.

Aktivni mailovi: `WHERE deleted_at IS NULL`.

---

## Prijedlozi

- Admin UI (threadovi + AI draft + filter po folder/label)  
- Slack/Telegram za `urgent`  
- Periodični cron za `sync-imap-reconcile.sh`
