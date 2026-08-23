-- Sudreg registry schema (zasebna baza: sudreg)
-- Ne mijesati s oriphiel (mail/FB inbox).

CREATE TABLE IF NOT EXISTS snapshots (
  id               BIGINT PRIMARY KEY,
  timestamp        TIMESTAMPTZ,
  available_until  TIMESTAMPTZ,
  staleness        INT,
  description      TEXT,
  selected_at      TIMESTAMPTZ,
  imported_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS companies (
  mbs                  TEXT PRIMARY KEY,
  oib                  TEXT,
  euid                 TEXT,
  status               TEXT,
  deleted              BOOLEAN NOT NULL DEFAULT FALSE,
  deleted_note         TEXT,
  nadlezni_sud         TEXT,
  naziv                TEXT,
  naziv_kraci          TEXT,
  adresa               TEXT,
  email                TEXT,
  temeljni_kapital     TEXT,
  pravni_oblik         TEXT,
  pretezita_djelatnost TEXT,
  snapshot_id          BIGINT REFERENCES snapshots(id),
  source_url           TEXT,
  scrape_ok            BOOLEAN,
  scrape_error         TEXT,
  fetched_at           TIMESTAMPTZ,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_companies_oib ON companies (oib);
CREATE INDEX IF NOT EXISTS idx_companies_email ON companies (email);
CREATE INDEX IF NOT EXISTS idx_companies_snapshot ON companies (snapshot_id);
CREATE INDEX IF NOT EXISTS idx_companies_naziv ON companies (naziv);
CREATE INDEX IF NOT EXISTS idx_companies_updated ON companies (updated_at DESC);

-- clanovi + zastupnici
CREATE TABLE IF NOT EXISTS company_people (
  id          BIGSERIAL PRIMARY KEY,
  mbs         TEXT NOT NULL REFERENCES companies(mbs) ON DELETE CASCADE,
  person_type TEXT NOT NULL CHECK (person_type IN ('clan', 'zastupnik')),
  ime         TEXT,
  oib         TEXT,
  tekst       TEXT,
  uloge       JSONB NOT NULL DEFAULT '[]'::jsonb,
  sort_order  INT NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_company_people_mbs ON company_people (mbs);
CREATE INDEX IF NOT EXISTS idx_company_people_oib ON company_people (oib);
CREATE INDEX IF NOT EXISTS idx_company_people_type ON company_people (person_type);

CREATE TABLE IF NOT EXISTS company_activities (
  id          BIGSERIAL PRIMARY KEY,
  mbs         TEXT NOT NULL REFERENCES companies(mbs) ON DELETE CASCADE,
  activity    TEXT NOT NULL,
  is_primary  BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order  INT NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_company_activities_mbs ON company_activities (mbs);

CREATE TABLE IF NOT EXISTS company_legal_relations (
  id          BIGSERIAL PRIMARY KEY,
  mbs         TEXT NOT NULL REFERENCES companies(mbs) ON DELETE CASCADE,
  tekst       TEXT NOT NULL,
  sort_order  INT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS company_financial_reports (
  id                   BIGSERIAL PRIMARY KEY,
  mbs                  TEXT NOT NULL REFERENCES companies(mbs) ON DELETE CASCADE,
  datum_predaje        TEXT,
  godina               TEXT,
  obracunsko_razdoblje TEXT,
  vrsta_izvjestaja     TEXT,
  sort_order           INT NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_company_fin_mbs ON company_financial_reports (mbs);

-- API /promjene redovi (delta / zadnje SCN)
CREATE TABLE IF NOT EXISTS promjene (
  snapshot_id  BIGINT NOT NULL REFERENCES snapshots(id),
  mbs          TEXT NOT NULL,
  change_id    BIGINT,
  vrijeme      TIMESTAMPTZ,
  scn          NUMERIC,
  imported_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (snapshot_id, mbs)
);
CREATE INDEX IF NOT EXISTS idx_promjene_mbs ON promjene (mbs);
CREATE INDEX IF NOT EXISTS idx_promjene_vrijeme ON promjene (vrijeme DESC);

CREATE TABLE IF NOT EXISTS sync_state (
  key          TEXT PRIMARY KEY,
  value        TEXT,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
