-- Brža pretraga po nazivu (ILIKE '%tekst%')
-- Pokreni u bazi sudreg (jednom).

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_companies_naziv_trgm
  ON companies USING gin (naziv gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_companies_naziv_kraci_trgm
  ON companies USING gin (naziv_kraci gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_companies_adresa_trgm
  ON companies USING gin (adresa gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_companies_status
  ON companies (status);
