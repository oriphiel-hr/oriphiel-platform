# Oriphiel Messaging — n8n + IMAP + AI

VPS: `186.240.157.80` (`srv1890026`)  
Skripte: `/root/oriphiel-ai/oriphiel_messaging/`  
Attachmenti: `/var/lib/oriphiel/attachments/email/{account_id}/`  
Baza: Postgres `oriphiel` (container `oriphiel-postgres`)

---

## Arhitektura (2 JSON-a)

| Datoteka (lokalno / Downloads) | Uloga |
|--------------------------------|--------|
| **`oriphiel-live-account-stub.json`** → `Oriphiel-Live-Account-Stub.json` | **Live IMAP** — puni pipeline (Normalize → Contact → Message → Ollama AI → Attachments). **Jedna kopija po mailboxu.** |
| **`oriphiel-mail-hub.json`** → `Oriphiel-Mail-Hub.json` | **Ops** — backfill / AI enrich / broj mailova. **Jedan workflow za sve accounte.** |
| `oriphiel-error-notify.json` | Error Workflow (obavijest kad padne) |
| `MULTI-ACCOUNT.md` | Kako dodati novi mailbox |

**Deprecated:** `new-mails-mario-vitt.json` / `New mails - mario.vitt@oriphiel.hr.json` — **ne koristi**.

```
  [Live Mail × N]          [Mail Hub × 1]
   IMAP → AI → disk         Account Config
                            ACTION=backfill|enrich|count
         \                     /
          \                   /
           ▼                 ▼
        Postgres oriphiel + /var/lib/oriphiel/attachments/
```

---

## Import u n8n (redoslijed)

1. Import `oriphiel-error-notify.json` → Active  
2. Import `Oriphiel-Live-Account-Stub.json`  
   - **Account Email** = `mario.vitt@oriphiel.hr` (ili drugi)  
   - IMAP credential za taj mailbox  
   - Settings → **Error Workflow** → Oriphiel — Error notify  
   - **Active**  
3. Import `Oriphiel-Mail-Hub.json` (ops; može Inactive dok ne treba)  
4. Stari **New mails - mario.vitt…** → **Deactivate** / Delete  

Credentials: Postgres, IMAP, SSH (isti kao prije).

---

## Live (novi mail)

Tok: IMAP → Account Email → Get Account → Normalize → Upsert Contact → Insert Message → **AI Enrich (Ollama)** → Update AI → attachmenti

- `thread_key` iz In-Reply-To / References / Message-ID  
- Disk: `/var/lib/oriphiel/attachments/email/{account_id}/`  
- **Ne** markiraj IMAP as read (Post-process prazno)  

### Novi mailbox

1. `cp accounts/*.env.example accounts/XYZ.env` na VPS-u + lozinka  
2. n8n: **Duplicate** Live Mail workflow → rename → novi IMAP credential → promijeni **Account Email**  
3. Hub: samo promijeni Account Config  

---

## Hub — ops (backfill / AI / broj)

Otvori **Account Config**:

| Polje | Primjer | Značenje |
|--------|---------|----------|
| `ACTION` | `count` / `backfill` / `enrich` | što pokrenuti |
| `ACCOUNT_EMAIL` | `mario.vitt@oriphiel.hr` | account |
| `ENV_FILE` | `accounts/oriphiel.hr-mario.vitt.env` | IMAP env |
| `STATUS_TAG` | `mario.vitt` | ime status JSON-a |
| `RUN_AI` | `0` / `1` | AI tijekom backfilla (sporo) |
| `RESET_BEFORE` | `0` / `1` | wipe prije uvoza |
| `BATCH_SIZE` | `50` | batch |
| `MARK_AS_SEEN` | `0` | IMAP Seen (preporuka OFF) |

Zatim **Manual Trigger**.

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

## Prijedlozi

- Admin UI (threadovi + AI draft)  
- Slack/Telegram za `urgent`  
- Sent folder sync  
- Zajednički Process Mail sub-workflow (live još uvijek 1 IMAP credential = 1 Live kopija)
