# PowerShell — Sudreg

SSH target: `root@186.240.157.80` (srv1890026)  
Kod: `scripts/sudreg/`  
Data (lokalno): `data/sudreg/`  
Data (VPS): `/opt/oriphiel-ai/data/sudreg/`

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
