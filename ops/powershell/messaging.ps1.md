# PowerShell — Messaging

SSH target: `root@186.240.157.80` (srv1890026)  
Kod: `scripts/oriphiel_messaging/`

---

## Provjera

```powershell
cd C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging

powershell -ExecutionPolicy Bypass -File .\Check-OriphielMessaging.ps1
powershell -ExecutionPolicy Bypass -File .\Check-OriphielMessaging.ps1 -AccountEmail mario.vitt@oriphiel.hr
powershell -ExecutionPolicy Bypass -File .\Check-OriphielMessaging.ps1 -RunUsefulSql
```

Na VPS-u:

```powershell
pwsh -File /root/oriphiel-ai/oriphiel_messaging/Check-OriphielMessaging.ps1 -Local
```

---

## Deploy skripti na VPS

```powershell
powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging\Deploy-ImapBackfill.ps1
```

---

## Ad-hoc SQL

```powershell
powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging\Invoke-OriphielSql.ps1

powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging\Invoke-OriphielSql.ps1 `
  -Sql "SELECT count(*) FROM messages;"
```

Više upita: [`../sql/messaging-useful.sql`](../sql/messaging-useful.sql)

---

## Setup (rijetko)

```powershell
# Schema / baza
powershell -ExecutionPolicy Bypass -File .\setup-oriphiel-messaging-db.ps1

# Attachment volume
powershell -ExecutionPolicy Bypass -File .\setup-attachments-volume.ps1
```

---

## Related

- Runbook: [`../runbooks/backfill-mail.md`](../runbooks/backfill-mail.md)
- n8n: http://186.240.157.80:5678
- Docs: [`../../scripts/oriphiel_messaging/n8n/UPUTE.md`](../../scripts/oriphiel_messaging/n8n/UPUTE.md)
