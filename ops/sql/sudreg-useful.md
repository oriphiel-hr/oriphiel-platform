# Ad-hoc SQL — Sudreg (Postgres `sudreg`)

Uvijek koristi PowerShell here-string `@"` … `"@` — prilagodi upit po potrebi.

**Setup (jednom po sesiji, s Windowsa):**

```powershell
cd C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg
. .\SudregPg.ps1
# Na VPS-u dodaj: -Local
```

**Pokretanje:** `Invoke-SudregPsql -Sql @" ... "@`  
**Na VPS-u:** `Invoke-SudregPsql -Local -Sql @" ... "@`

Batch file: [`sudreg-useful.sql`](sudreg-useful.sql) · deploy: `scripts/sudreg/sql/useful-selects.sql`  
Ili: `Check-Sudreg.ps1 -RunUsefulSql`

---

## Napredak / sync

```powershell
Invoke-SudregPsql -Sql @"
SELECT key, left(value, 100) AS value, updated_at
FROM sync_state
ORDER BY key;
"@
```

```powershell
Invoke-SudregPsql -Sql @"
SELECT id, timestamp, available_until, imported_at
FROM snapshots
ORDER BY id DESC
LIMIT 15;
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

## Na VPS-u (isti SQL, bash)

```bash
docker exec -i oriphiel-postgres psql -U oriphiel -d sudreg -c "
SELECT key, left(value, 100) AS value, updated_at FROM sync_state ORDER BY key;
"
```
