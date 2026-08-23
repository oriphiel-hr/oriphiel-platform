# Ad-hoc SQL — Sudreg (Postgres `sudreg`)

Host: **srv1890026** (`186.240.157.80`) · container `oriphiel-postgres` · baza `sudreg`

---

## Gdje si? (obavezno `cd`)

| Okolina | Direktorij | Napomena |
|---------|------------|----------|
| **Windows** | `C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg` | PowerShell |
| **VPS (SSH bash)** | `/opt/oriphiel-ai/scripts/sudreg` | **ne** `~/scripts/...` |
| SQL batch file (VPS) | `/opt/oriphiel-ai/scripts/sudreg/sql/useful-selects.sql` | `.sql`, ne `.sq` |
| Podaci (VPS) | `/opt/oriphiel-ai/data/sudreg/` | JSON cache, logovi |

> **`Invoke-SudregPsql` ne radi u bashu** (`command not found`). To je PowerShell funkcija.  
> Na VPS-u u SSH sesiji koristi **docker psql** (ispod) ili **`pwsh`** s punom putanjom.

---

## VPS — bash (preporučeno kad si već na SSH)

```bash
ssh root@186.240.157.80
cd /opt/oriphiel-ai/scripts/sudreg
```

Jedan upit (prilagodi SQL):

```bash
docker exec -i oriphiel-postgres psql -U oriphiel -d sudreg -c "
SELECT id, timestamp, available_until, imported_at
FROM snapshots
ORDER BY id DESC
LIMIT 15;
"
```

Cijeli useful-selects file:

```bash
cd /opt/oriphiel-ai/scripts/sudreg
docker exec -i oriphiel-postgres psql -U oriphiel -d sudreg -f - < sql/useful-selects.sql
```

Check skripta (PowerShell na VPS-u):

```bash
cd /opt/oriphiel-ai/scripts/sudreg
pwsh -File ./Check-Sudreg.ps1 -Local -DbDetail
pwsh -File ./Check-Sudreg.ps1 -Local -RunUsefulSql
```

---

## VPS — pwsh + `@"` (isti oblik kao Windows)

```bash
cd /opt/oriphiel-ai/scripts/sudreg
pwsh
```

U **pwsh** promptu (ne u bashu):

```powershell
. ./SudregPg.ps1
Invoke-SudregPsql -Local -Sql @"
SELECT id, timestamp, available_until, imported_at
FROM snapshots
ORDER BY id DESC
LIMIT 15;
"@
```

---

## Windows — PowerShell + `@"` … `"@`

```powershell
cd C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg
. .\SudregPg.ps1
```

**Pokretanje:** `Invoke-SudregPsql -Sql @" ... "@` (SSH na VPS)  
**Lokalno na VPS-u:** dodaj `-Local`

Batch file: [`sudreg-useful.sql`](sudreg-useful.sql) · deploy: `scripts/sudreg/sql/useful-selects.sql`

---

## Napredak ubacivanja (live) — ovo nije SQL

Dok sync radi, napredak (`phase`, `done`/`total`, `ok`/`err`, `STANJE`) ide u **datoteku**, ne u `snapshots` tablicu.

| Što | Put / naredba |
|-----|----------------|
| Progress file (VPS) | `/opt/oriphiel-ai/data/sudreg/run/progress.json` |
| Lock | `/opt/oriphiel-ai/data/sudreg/run/lock.json` |
| Logovi | `/opt/oriphiel-ai/data/sudreg/logs/` |
| Puna provjera | `Check-Sudreg.ps1 -Local` |
| Samo status | `Sudreg-Control.ps1 -Status -Local` ili `Check-Sudreg.ps1 -StatusOnly -Local` |

### VPS — bash

```bash
cd /opt/oriphiel-ai/scripts/sudreg

# Live napredak (ponavljaj)
watch -n2 cat /opt/oriphiel-ai/data/sudreg/run/progress.json

# Ili jednom
cat /opt/oriphiel-ai/data/sudreg/run/progress.json

# Status: phase, done/total, brojevi u bazi
pwsh -File ./Sudreg-Control.ps1 -Status -Local
pwsh -File ./Check-Sudreg.ps1 -Local
pwsh -File ./Check-Sudreg.ps1 -Local -StatusOnly
```

### Windows — PowerShell

```powershell
cd C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg
powershell -ExecutionPolicy Bypass -File .\Check-Sudreg.ps1
powershell -ExecutionPolicy Bypass -File .\Sudreg-Control.ps1 -Status
```

U `progress.json` gledaj npr. `status`, `phase`, `done`, `total`, `message` (npr. `sync_subjects` s `done=1200` / `total=5000`).

**SQL ispod** (`sync_state`, `snapshots`, broj firmi) = stanje **u bazi nakon / tijekom importa**, ne “percent bar” iz progress filea.

---

## Baza — sync_state / snapshoti (nakon ili usporedba)

Primjeri: **Windows** (`Invoke-SudregPsql`). Na VPS-u u **pwsh** dodaj `-Local`, ili bash `docker` iz uvoda.

```powershell
Invoke-SudregPsql -Sql @"
SELECT key, left(value, 100) AS value, updated_at
FROM sync_state
ORDER BY key;
"@
```

Ključevi tipično: `last_imported_snapshot_id`, `last_import_ok_count`, `last_import_err_count`.

```powershell
Invoke-SudregPsql -Sql @"
SELECT id, timestamp, available_until, imported_at
FROM snapshots
ORDER BY id DESC
LIMIT 15;
"@
```

```powershell
Invoke-SudregPsql -Sql @"
SELECT
  (SELECT count(*) FROM companies) AS companies,
  (SELECT count(*) FROM company_people) AS people,
  (SELECT value FROM sync_state WHERE key = 'last_imported_snapshot_id') AS last_imported,
  (SELECT value FROM sync_state WHERE key = 'last_import_ok_count') AS last_ok,
  (SELECT value FROM sync_state WHERE key = 'last_import_err_count') AS last_err;
"@
```

---

## Brojevi

```powershell
Invoke-SudregPsql -Sql @"
SELECT 'companies' AS what, count(*)::text AS n FROM companies
UNION ALL SELECT 'company_people', count(*)::text FROM company_people
UNION ALL SELECT 'company_activities', count(*)::text FROM company_activities
UNION ALL SELECT 'company_legal_relations', count(*)::text FROM company_legal_relations
UNION ALL SELECT 'company_financial_reports', count(*)::text FROM company_financial_reports
UNION ALL SELECT 'promjene', count(*)::text FROM promjene
UNION ALL SELECT 'snapshots', count(*)::text FROM snapshots;
"@
```

```powershell
Invoke-SudregPsql -Sql @"
SELECT
  count(*) AS companies,
  count(*) FILTER (WHERE scrape_ok IS TRUE) AS scrape_ok,
  count(*) FILTER (WHERE scrape_ok IS FALSE) AS scrape_fail,
  count(*) FILTER (WHERE scrape_ok IS NULL) AS scrape_null,
  count(*) FILTER (WHERE deleted) AS deleted
FROM companies;
"@
```

```powershell
Invoke-SudregPsql -Sql @"
SELECT coalesce(status,'(null)') AS status, count(*) AS n
FROM companies
GROUP BY status
ORDER BY n DESC
LIMIT 25;
"@
```

```powershell
Invoke-SudregPsql -Sql @"
SELECT snapshot_id, count(*) AS n
FROM companies
GROUP BY snapshot_id
ORDER BY snapshot_id DESC NULLS LAST
LIMIT 20;
"@
```

---

## Pretraga firmi (prilagodi OIB / naziv / MBS)

```powershell
Invoke-SudregPsql -Sql @"
SELECT * FROM companies WHERE oib = '12345678901';
"@
```

```powershell
Invoke-SudregPsql -Sql @"
SELECT mbs, oib, left(naziv, 50) AS naziv, status, email, updated_at
FROM companies
WHERE naziv ILIKE '%oriphiel%'
ORDER BY updated_at DESC
LIMIT 20;
"@
```

```powershell
Invoke-SudregPsql -Sql @"
SELECT mbs, left(coalesce(naziv,''), 45) AS naziv, oib, status,
       scrape_ok, snapshot_id, updated_at
FROM companies
ORDER BY updated_at DESC NULLS LAST
LIMIT 25;
"@
```

```powershell
Invoke-SudregPsql -Sql @"
SELECT mbs, left(naziv, 40) AS naziv, left(scrape_error, 80) AS scrape_error, updated_at
FROM companies
WHERE scrape_ok IS FALSE
ORDER BY updated_at DESC
LIMIT 30;
"@
```

---

## Osobe / djelatnosti / promjene

```powershell
Invoke-SudregPsql -Sql @"
SELECT cp.person_type, count(*) AS n
FROM company_people cp
GROUP BY cp.person_type;
"@
```

```powershell
Invoke-SudregPsql -Sql @"
SELECT * FROM company_people WHERE mbs = '080000000' ORDER BY person_type, sort_order;
"@
```

```powershell
Invoke-SudregPsql -Sql @"
SELECT left(cp.ime, 40) AS ime, cp.oib, cp.person_type, cp.mbs,
       left(c.naziv, 35) AS firma
FROM company_people cp
JOIN companies c ON c.mbs = cp.mbs
WHERE cp.oib IS NOT NULL AND btrim(cp.oib) <> ''
ORDER BY cp.id DESC
LIMIT 20;
"@
```

```powershell
Invoke-SudregPsql -Sql @"
SELECT left(activity, 60) AS activity, count(*) AS n
FROM company_activities
GROUP BY activity
ORDER BY n DESC
LIMIT 20;
"@
```

```powershell
Invoke-SudregPsql -Sql @"
SELECT snapshot_id, count(*) AS mbs_count,
       min(vrijeme) AS min_t, max(vrijeme) AS max_t
FROM promjene
GROUP BY snapshot_id
ORDER BY snapshot_id DESC
LIMIT 15;
"@
```

```powershell
Invoke-SudregPsql -Sql @"
SELECT p.snapshot_id, p.mbs, p.vrijeme, left(c.naziv, 40) AS naziv
FROM promjene p
LEFT JOIN companies c ON c.mbs = p.mbs
ORDER BY p.vrijeme DESC NULLS LAST
LIMIT 20;
"@
```

---

## Jedna firma (zamijeni MBS)

```powershell
Invoke-SudregPsql -Sql @"
SELECT * FROM companies WHERE mbs = '080000000';
SELECT * FROM company_people WHERE mbs = '080000000' ORDER BY person_type, sort_order;
SELECT * FROM company_activities WHERE mbs = '080000000' ORDER BY is_primary DESC, sort_order;
SELECT * FROM company_legal_relations WHERE mbs = '080000000';
SELECT * FROM company_financial_reports WHERE mbs = '080000000';
"@
```

---

## Brzi bash (VPS) — kopiraj isti SQL

```bash
cd /opt/oriphiel-ai/scripts/sudreg
docker exec -i oriphiel-postgres psql -U oriphiel -d sudreg -c "
SELECT key, left(value, 100) AS value, updated_at FROM sync_state ORDER BY key;
"
```
