-- Sudreg — korisni SELECT-ovi
-- Baza: Postgres `sudreg` (container oriphiel-postgres)
-- Vault: ops/sql/  |  Izvor (deploy): scripts/sudreg/sql/useful-selects.sql
--
-- Na VPS-u:
--   docker exec -i oriphiel-postgres psql -U oriphiel -d sudreg -f - < sudreg-useful.sql
-- Ili: Check-Sudreg.ps1 -DbDetail -Local

-- ========== NAPREDAK / SYNC ==========
SELECT key, left(value, 100) AS value, updated_at
FROM sync_state
ORDER BY key;

SELECT id, timestamp, available_until, imported_at
FROM snapshots
ORDER BY id DESC
LIMIT 15;

-- ========== BROJEVI ==========
SELECT 'companies' AS what, count(*)::text AS n FROM companies
UNION ALL SELECT 'company_people', count(*)::text FROM company_people
UNION ALL SELECT 'company_activities', count(*)::text FROM company_activities
UNION ALL SELECT 'company_legal_relations', count(*)::text FROM company_legal_relations
UNION ALL SELECT 'company_financial_reports', count(*)::text FROM company_financial_reports
UNION ALL SELECT 'promjene', count(*)::text FROM promjene
UNION ALL SELECT 'snapshots', count(*)::text FROM snapshots;

-- Scrape uspjeh
SELECT
  count(*) AS companies,
  count(*) FILTER (WHERE scrape_ok IS TRUE) AS scrape_ok,
  count(*) FILTER (WHERE scrape_ok IS FALSE) AS scrape_fail,
  count(*) FILTER (WHERE scrape_ok IS NULL) AS scrape_null,
  count(*) FILTER (WHERE deleted) AS deleted
FROM companies;

-- Po statusu firme
SELECT coalesce(status,'(null)') AS status, count(*) AS n
FROM companies
GROUP BY status
ORDER BY n DESC
LIMIT 25;

-- Po snapshotu
SELECT snapshot_id, count(*) AS n
FROM companies
GROUP BY snapshot_id
ORDER BY snapshot_id DESC NULLS LAST
LIMIT 20;

-- ========== PRETRAGA FIRM ==========
-- Po OIB-u: SELECT * FROM companies WHERE oib = '12345678901';

SELECT mbs, oib, left(naziv, 50) AS naziv, status, email, updated_at
FROM companies
WHERE naziv ILIKE '%oriphiel%'
ORDER BY updated_at DESC
LIMIT 20;

SELECT mbs, left(coalesce(naziv,''), 45) AS naziv, oib, status,
       scrape_ok, snapshot_id, updated_at
FROM companies
ORDER BY updated_at DESC NULLS LAST
LIMIT 25;

SELECT mbs, left(naziv, 40) AS naziv, left(scrape_error, 80) AS scrape_error, updated_at
FROM companies
WHERE scrape_ok IS FALSE
ORDER BY updated_at DESC
LIMIT 30;

-- ========== OSOBE ==========
SELECT cp.person_type, count(*) AS n
FROM company_people cp
GROUP BY cp.person_type;

SELECT left(cp.ime, 40) AS ime, cp.oib, cp.person_type, cp.mbs,
       left(c.naziv, 35) AS firma
FROM company_people cp
JOIN companies c ON c.mbs = cp.mbs
WHERE cp.oib IS NOT NULL AND btrim(cp.oib) <> ''
ORDER BY cp.id DESC
LIMIT 20;

-- ========== DJELATNOSTI ==========
SELECT left(activity, 60) AS activity, count(*) AS n
FROM company_activities
GROUP BY activity
ORDER BY n DESC
LIMIT 20;

-- ========== PROMJENE ==========
SELECT snapshot_id, count(*) AS mbs_count,
       min(vrijeme) AS min_t, max(vrijeme) AS max_t
FROM promjene
GROUP BY snapshot_id
ORDER BY snapshot_id DESC
LIMIT 15;

SELECT p.snapshot_id, p.mbs, p.vrijeme, left(c.naziv, 40) AS naziv
FROM promjene p
LEFT JOIN companies c ON c.mbs = p.mbs
ORDER BY p.vrijeme DESC NULLS LAST
LIMIT 20;

-- ========== JEDNA FIRMA (zamijeni MBS) ==========
/*
SELECT * FROM companies WHERE mbs = '080000000';
SELECT * FROM company_people WHERE mbs = '080000000' ORDER BY person_type, sort_order;
SELECT * FROM company_activities WHERE mbs = '080000000' ORDER BY is_primary DESC, sort_order;
SELECT * FROM company_legal_relations WHERE mbs = '080000000';
SELECT * FROM company_financial_reports WHERE mbs = '080000000';
*/
