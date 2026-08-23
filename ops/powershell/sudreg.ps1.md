# PowerShell — Sudreg

SSH target: `root@186.240.157.80` (srv1890026)  
Kod: `scripts/sudreg/`  
Data (lokalno): `data/sudreg/`  
Data (VPS): `/opt/oriphiel-ai/data/sudreg/`

---

## Na VPS-u (SSH bash) — prvo `cd`

```bash
ssh root@186.240.157.80
cd /opt/oriphiel-ai/scripts/sudreg
```

**Ne radi u bashu:** `Invoke-SudregPsql` → `command not found`

### Napredak ubacivanja (live)

```bash
# phase / done / total
watch -n2 cat /opt/oriphiel-ai/data/sudreg/run/progress.json

pwsh -File ./Sudreg-Control.ps1 -Status -Local
pwsh -File ./Check-Sudreg.ps1 -Local
```

### SQL / check

```bash
# Jedan SQL upit
docker exec -i oriphiel-postgres psql -U oriphiel -d sudreg -c "
SELECT id, timestamp, available_until, imported_at
FROM snapshots ORDER BY id DESC LIMIT 15;
"

# Cijeli useful-selects
docker exec -i oriphiel-postgres psql -U oriphiel -d sudreg -f - < sql/useful-selects.sql

# Check skripta
pwsh -File ./Check-Sudreg.ps1 -Local -DbDetail
```

**pwsh + `@"`:** `cd /opt/oriphiel-ai/scripts/sudreg` → `pwsh` → `. ./SudregPg.ps1` → `Invoke-SudregPsql -Local -Sql @"..."@`

Više: [`../sql/sudreg-useful.md`](../sql/sudreg-useful.md)

---

## Status / check

```powershell
cd C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg

powershell -ExecutionPolicy Bypass -File .\Check-Sudreg.ps1
powershell -ExecutionPolicy Bypass -File .\Check-Sudreg.ps1 -DbDetail
powershell -ExecutionPolicy Bypass -File .\Check-Sudreg.ps1 -StatusOnly
powershell -ExecutionPolicy Bypass -File .\Check-Sudreg.ps1 -RunUsefulSql

# Na VPS-u
pwsh -File /opt/oriphiel-ai/scripts/sudreg/Check-Sudreg.ps1 -Local
pwsh -File /opt/oriphiel-ai/scripts/sudreg/Sudreg-Control.ps1 -Status -Local
```

---

## Deploy na VPS

```powershell
powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Deploy-SudregToVps.ps1
powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Deploy-SudregToVps.ps1 -RunInstall
powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Deploy-SudregToVps.ps1 -SkipUpload -RunBootstrap
```

---

## Update / sync

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Update-Sudreg.ps1 `
  -FetchPromjeneFirst -SkipExistingPromjene

powershell -NoProfile -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Run-SudregDaily.ps1
powershell -ExecutionPolicy Bypass -File .\Sudreg-Control.ps1 -Status
```

---

## Ad-hoc SQL (`@"` … `"@`)

Svi gotovi upiti (prilagodi po potrebi):  
→ [`../sql/sudreg-useful.md`](../sql/sudreg-useful.md)

Primjer:

```powershell
cd C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg
. .\SudregPg.ps1

Invoke-SudregPsql -Sql @"
SELECT key, left(value, 100) AS value, updated_at
FROM sync_state
ORDER BY key;
"@
```

Na VPS-u dodaj `-Local`. Batch: [`../sql/sudreg-useful.sql`](../sql/sudreg-useful.sql)

---

## Snapshot / pretraga

```powershell
& .\Get-SudregSnapshots.ps1 -Latest
& .\Get-SudregSubject.ps1 -Mbs 081617997 -AsJson
& .\Compare-SudregPromjene.ps1
```

---

## Related

- Docs: [`../../scripts/sudreg/UPUTE.md`](../../scripts/sudreg/UPUTE.md)
