# Oriphiel Messaging

IMAP → n8n / Python → Postgres (`oriphiel`) + disk attachmenti + Ollama AI.

## Dokumentacija

| Datoteka | Sadržaj |
|----------|---------|
| [n8n/UPUTE.md](n8n/UPUTE.md) | Glavne upute (Live + Hub) |
| [n8n/MULTI-ACCOUNT.md](n8n/MULTI-ACCOUNT.md) | Novi mailbox |
| `Oriphiel-Messaging-Upute.docx` | Word (generira `build-upute-docx.py`) |
| `sql/useful-selects.sql` | Korisni SQL |

## n8n JSON (Downloads)

| JSON | Uloga |
|------|--------|
| `Oriphiel-Live-Account-Stub.json` | Live IMAP + AI + attachmenti (po accountu) |
| `Oriphiel-Mail-Hub.json` | Backfill / enrich / count (svi accounti) |
| `oriphiel-error-notify.json` | Error notify |

**Ne koristi:** `New mails - mario.vitt@oriphiel.hr.json` (deprecated).

## VPS

```
/root/oriphiel-ai/oriphiel_messaging/
```

Deploy: `Deploy-ImapBackfill.ps1` → `root@186.240.157.80`

## Brze naredbe

```bash
# status backfill
watch -n2 cat /tmp/oriphiel-imap-backfill-mario.vitt.json

# AI enrich status
watch -n5 cat /tmp/oriphiel-ai-enrich-mario.vitt.json

# provjera
bash check-messaging.sh
```
