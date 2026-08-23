# Ops index — “Bitwarden za naredbe”

Jedan ulaz za SQL, PowerShell, bash i runbookove.

**Repo:** https://github.com/oriphiel-hr/oriphiel-platform  
**Lokalno:** `C:\GIT_PROJEKTI\oriphiel-platform`  
**Hostovi:** [`infra/hosts.yaml`](../infra/hosts.yaml)

> Tajne (lozinke, API ključevi) → **Bitwarden**. Ovdje samo naredbe i upute.

---

## Projekti

| Projekt | Kod | GitHub | VPS |
|---------|-----|--------|-----|
| Ravnopar | [`ravnopar/`](../ravnopar/) | [tree/ravnopar](https://github.com/oriphiel-hr/oriphiel-platform/tree/master/ravnopar) | `186.240.157.39` → `/var/www/Render/ravnopar` |
| Messaging | [`scripts/oriphiel_messaging/`](../scripts/oriphiel_messaging/) | [tree/messaging](https://github.com/oriphiel-hr/oriphiel-platform/tree/master/scripts/oriphiel_messaging) | `186.240.157.80` → `/root/oriphiel-ai/oriphiel_messaging` |
| Sudreg | [`scripts/sudreg/`](../scripts/sudreg/) | [tree/sudreg](https://github.com/oriphiel-hr/oriphiel-platform/tree/master/scripts/sudreg) | `/opt/oriphiel-ai/scripts/sudreg` |
| Open WebUI | [`assets/`](../assets/), [`scripts/deploy-all.ps1`](../scripts/deploy-all.ps1) | — | `https://ai.oriph.io` |

---

## SQL (ad-hoc = uvijek `@"` … `"@`)

Primarni oblik za prilagodbu: **`.md`** s PowerShell here-stringom.  
`.sql` = batch za `psql -f` / `Check-*-RunUsefulSql`.

| Ad-hoc (prilagodi) | Batch | Baza |
|--------------------|-------|------|
| [sql/messaging-useful.md](sql/messaging-useful.md) | [`.sql`](sql/messaging-useful.sql) | Postgres `oriphiel` |
| [sql/sudreg-useful.md](sql/sudreg-useful.md) | [`.sql`](sql/sudreg-useful.sql) | Postgres `sudreg` |
| [sql/ravnopar-mysql.md](sql/ravnopar-mysql.md) | [`.sql`](sql/ravnopar-mysql.sql) | MySQL `ravnopar` |

---

## PowerShell (Windows → VPS)

| Datoteka | Sadržaj |
|----------|---------|
| [powershell/messaging.ps1.md](powershell/messaging.ps1.md) | Check, deploy, SQL, backfill |
| [powershell/sudreg.ps1.md](powershell/sudreg.ps1.md) | Status, deploy, daily update |

---

## Bash (na VPS-u)

| Datoteka | Sadržaj |
|----------|---------|
| [bash/vps-checks.sh.md](bash/vps-checks.sh.md) | Health checks messaging / sudreg / ravnopar / ollama |

---

## Runbooks

| Datoteka | Kada |
|----------|------|
| [runbooks/backfill-mail.md](runbooks/backfill-mail.md) | IMAP backfill + AI enrich |
| [runbooks/deploy-ravnopar.md](runbooks/deploy-ravnopar.md) | Deploy / rebuild Ravnopar na VPS |

---

## Duža dokumentacija

| Mjesto | Sadržaj |
|--------|---------|
| [`docs/`](../docs/) | Open WebUI Word upute |
| [`scripts/oriphiel_messaging/n8n/UPUTE.md`](../scripts/oriphiel_messaging/n8n/UPUTE.md) | n8n Live + Hub |
| [`scripts/sudreg/UPUTE.md`](../scripts/sudreg/UPUTE.md) | Sudreg sync |
| [`ravnopar/docs/`](../ravnopar/docs/) | Monitoring, Render env, SEO |

---

## Brzi linkovi

- n8n: http://186.240.157.80:5678  
- Open WebUI: https://ai.oriph.io  
- Ravnopar: https://ravnopar.com  
- GitHub org: https://github.com/oriphiel-hr  
