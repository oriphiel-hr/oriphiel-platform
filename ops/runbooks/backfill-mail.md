# Runbook — IMAP backfill + AI enrich

Messaging na VPS `186.240.157.80`.  
Kod: `/root/oriphiel-ai/oriphiel_messaging/`  
n8n Hub: http://186.240.157.80:5678 → **Oriphiel — Mail Hub**

---

## Prije početka

1. Deploy najnovijih skripti s Windowsa:
   ```powershell
   powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging\Deploy-ImapBackfill.ps1
   ```
2. Provjeri da **nema** dva backfill procesa odjednom.
3. `RESET_BEFORE=1` briše postojeće poruke za account — koristi **samo** kad namjerno želiš reset.

---

## Opcija A — n8n Mail Hub (preporučeno)

1. Otvori **Oriphiel — Mail Hub**
2. U **Account Config** postavi `ACCOUNT_EMAIL` (npr. `mario.vitt@oriphiel.hr`)
3. `ACTION`:
   - `backfill` — IMAP → DB (obično `RUN_AI=0`, `RESET_BEFORE=0`)
   - `enrich` — samo Ollama na porukama bez AI
   - `count` — brojevi
4. Pokreni Manual Trigger za željeni action
5. Status na VPS-u:
   ```bash
   watch -n2 cat /tmp/oriphiel-imap-backfill-mario.vitt.json
   watch -n5 cat /tmp/oriphiel-ai-enrich-mario.vitt.json
   ```

---

## Opcija B — SSH / nohup

```bash
ssh root@186.240.157.80
cd /root/oriphiel-ai/oriphiel_messaging

# Zaustavi stare procese ako treba
pkill -f sync-imap-backfill.py || true
pkill -f enrich-existing-messages.py || true

# Backfill (bez AI)
nohup env ACCOUNT_EMAIL=mario.vitt@oriphiel.hr RUN_AI=0 RESET_BEFORE=0 BATCH_SIZE=50 \
  bash sync-imap-backfill.sh >>/tmp/oriphiel-imap-backfill-last.log 2>&1 &

# AI enrich postojećih
nohup env ACCOUNT_EMAIL=mario.vitt@oriphiel.hr ONLY_MISSING=1 LIMIT=0 BATCH_SIZE=10 \
  python3 -u enrich-existing-messages.py >>/tmp/oriphiel-ai-enrich-last.log 2>&1 &
```

---

## Provjera

```powershell
powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging\Check-OriphielMessaging.ps1
```

SQL: [`../sql/messaging-useful.sql`](../sql/messaging-useful.sql) — broj `without_ai`, `messages_with_ai`.

---

## Tipični problemi

| Simptom | Uzrok | Fix |
|---------|-------|-----|
| Broj poruka pada / reset | dva backfilla + `RESET_BEFORE=1` | `pkill`, jedan run, `RESET_BEFORE=0` |
| AI 0 / N | backfill s `RUN_AI=0` | pokreni Hub `enrich` |
| n8n SSH timeout | dugi proces | Hub koristi `nohup` (ne čekaj u SSH nodu) |
| `.env` syntax error | paste shell u env | očisti `.env`, quote password |

---

## Related

- [`../powershell/messaging.ps1.md`](../powershell/messaging.ps1.md)
- [`../../scripts/oriphiel_messaging/n8n/UPUTE.md`](../../scripts/oriphiel_messaging/n8n/UPUTE.md)
- [`../../scripts/oriphiel_messaging/n8n/MULTI-ACCOUNT.md`](../../scripts/oriphiel_messaging/n8n/MULTI-ACCOUNT.md)
