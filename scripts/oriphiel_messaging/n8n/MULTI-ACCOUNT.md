# Oriphiel mail — 2 JSON-a (bez New mails - mario…)

## Datoteke

| Datoteka | Uloga |
|----------|--------|
| `oriphiel-live-account-stub.json` | **Live IMAP** (puni pipeline: AI + attachmenti). 1 kopija po mailboxu. |
| `oriphiel-mail-hub.json` | **Ops**: backfill / AI enrich / broj mailova (svi accounti). |

`New mails - mario.vitt@oriphiel.hr.json` — **deprecated**. Ne koristi.

---

## Setup mario.vitt (zamjena starog workflowa)

1. Import **Oriphiel-Live-Account-Stub** (Downloads: `Oriphiel-Live-Account-Stub.json`)
2. **Account Email** = `mario.vitt@oriphiel.hr`
3. IMAP credential = postojeći
4. **Active**
5. Stari **New mails - mario.vitt…** → **Deactivate** (ili obriši)
6. Import **Oriphiel-Mail-Hub** za backfill / enrich / count

Error Workflow: Settings na Live workflowu → `Oriphiel — Error notify`

---

## Novi account (npr. info@)

1. `accounts/info.env` na VPS-u  
2. Duplicate **Live Mail** workflow → rename → novi IMAP credential → Account Email  
3. Hub: samo promijeni Account Config  

---

## Hub — Account Config

- `ACTION` = `count` | `backfill` | `enrich`
- `ACCOUNT_EMAIL`, `ENV_FILE`, `STATUS_TAG`
- `RUN_AI`, `RESET_BEFORE`, `BATCH_SIZE`, `MARK_AS_SEEN`
