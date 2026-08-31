-- Oriphiel CRM (odvojeno od sudreg i oriphiel)
-- Enrichment: web, bilješke, podaci koje NIJE dao Sudreg sync

CREATE TABLE IF NOT EXISTS company_websites (
  id            BIGSERIAL PRIMARY KEY,
  mbs           TEXT NOT NULL,
  oib           TEXT,
  website       TEXT NOT NULL,
  is_primary    BOOLEAN NOT NULL DEFAULT FALSE,
  role          TEXT,
  source        TEXT NOT NULL DEFAULT 'web_finder',
  confidence    TEXT,
  evidence_url  TEXT,
  score         INTEGER,
  verified_by   TEXT,
  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (mbs, website)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_company_websites_one_primary
  ON company_websites (mbs) WHERE is_primary;

CREATE INDEX IF NOT EXISTS idx_crm_websites_mbs ON company_websites (mbs);
CREATE INDEX IF NOT EXISTS idx_crm_websites_oib ON company_websites (oib);
CREATE INDEX IF NOT EXISTS idx_crm_websites_website ON company_websites (website);
CREATE INDEX IF NOT EXISTS idx_crm_websites_updated ON company_websites (updated_at DESC);

COMMENT ON TABLE company_websites IS 'Web domene potvrđene finderom / ručno — više po MBS, jedna glavna';
COMMENT ON COLUMN company_websites.is_primary IS 'Glavna domena (corporate)';
COMMENT ON COLUMN company_websites.role IS 'corporate | shop | booking | campaign | legacy | other';
COMMENT ON COLUMN company_websites.source IS 'web_finder | manual | migrated | web_finder_batch';
