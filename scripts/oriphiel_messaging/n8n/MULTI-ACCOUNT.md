# Oriphiel mail — multi-account (bez dupliciranja pipelinea)

## Datoteke

| Datoteka | Uloga |
|----------|--------|
| **`oriphiel-live-process.json`** | **Zajednički** Live pipeline (Get Account → Message → AI → Attachments). **Jednom.** |
| **`oriphiel-live-imap-stub.json`** | **Tanki** IMAP stub. **1 kopija po mailboxu** → zove Process. |
| `oriphiel-mail-hub.json` | Ops: backfill / enrich / count (svi accounti, mijenjaš Config). |
| `oriphiel-error-notify.json` | Error Workflow |

**Deprecated:**
- `oriphiel-live-account-stub.json` (stari monolit IMAP+AI u jednom)
- `new-mails-mario-vitt.json` / `New mails - mario.vitt…`

Downloads (nakon kopiranja):
- `Oriphiel-Live-Process.json`
- `Oriphiel-Live-Imap-Stub.json`
- `Oriphiel-Mail-Hub.json`

---

## Arhitektura

```
  [IMAP Stub × N]                    [Mail Hub × 1]
   IMAP → Account Email                   Account Config
        → Call Live Process               ACTION=backfill|enrich|count
                 \                              /
                  \                            /
                   ▼                          ▼
        [Live Process × 1]          SSH / Python / SQL
        Get Account → Normalize → Contact → Message → AI → Attachments
                         ▼
              Postgres + /var/lib/oriphiel/attachments/
```

- **Insert Message / AI / Attachments** = jednom u Process (dijele svi stubovi).
- **Samo IMAP + email** se duplicira po mailboxu.

---

## Setup (prvi put)

1. Import **Oriphiel-Live-Process** → spoji Postgres + SSH credentials → **Active**  
2. Import **Oriphiel-Live-Imap-Stub**  
   - IMAP credential = mario (ili drugi)  
   - **Account Email** = `mario.vitt@oriphiel.hr`  
   - Nod **Call Live Process** → odaberi workflow `Oriphiel — Live Process (shared)` (ako nije već po imenu)  
   - Error Workflow → Error notify  
   - **Active**  
3. Import **Oriphiel-Mail-Hub** (ops)  
4. Stari monolit / `New mails - mario…` → **Deactivate**

---

## Novi account (npr. info@)

1. VPS: `cp accounts/*.env.example accounts/info.env` + lozinka  
2. Red u `channels_accounts` (ako nema)  
3. n8n: **Duplicate** samo **IMAP Stub** (ne Process!)  
4. Rename → novi IMAP credential → **Account Email** = `info@…`  
5. Call Live Process i dalje pokazuje na **isti** Process  
6. Active  

Hub: samo promijeni Account Config (`ACCOUNT_EMAIL`, `ENV_FILE`, `STATUS_TAG`).

---

## Hub — Account Config (text polja)

1. Otvori nod **Account Config**
2. Upiši vrijednosti — **u imenu polja** piše što smiješ unijeti
3. **Manual Trigger** → Execute workflow

| Polje (label u n8n) | Dopušteno |
|---------------------|-----------|
| `ACTION (count \| backfill \| enrich)` | točno jedna od te tri |
| `RUN_AI (0=ne \| 1=da, backfill)` | `0` ili `1` |
| `RESET_BEFORE (0=ne \| 1=da, …)` | `0` ili `1` |
| `MARK_AS_SEEN (0=ne \| 1=da, …)` | `0` ili `1` |
| `ACCOUNT_EMAIL (npr. …)` | email adresa |
| `ENV_FILE (npr. …)` | putanja na VPS-u |
| `STATUS_TAG (…)` | kratki tag |
| `BATCH_SIZE (broj, npr. 50)` | broj |

Nema Form URL / localhost problema.