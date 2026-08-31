-- Više domena po tvrtki (MBS): jedna glavna, ostale u popisu.

ALTER TABLE company_websites ADD COLUMN IF NOT EXISTS is_primary BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE company_websites ADD COLUMN IF NOT EXISTS role TEXT;

UPDATE company_websites SET is_primary = TRUE WHERE is_primary IS DISTINCT FROM TRUE;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY (c.conkey)
    WHERE t.relname = 'company_websites'
      AND c.contype = 'p'
      AND a.attname = 'mbs'
      AND array_length(c.conkey, 1) = 1
  ) THEN
    ALTER TABLE company_websites ADD COLUMN IF NOT EXISTS id BIGSERIAL;
    ALTER TABLE company_websites DROP CONSTRAINT company_websites_pkey;
    ALTER TABLE company_websites ADD PRIMARY KEY (id);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_company_websites_mbs_website
  ON company_websites (mbs, website);

CREATE UNIQUE INDEX IF NOT EXISTS idx_company_websites_one_primary
  ON company_websites (mbs) WHERE is_primary;

CREATE INDEX IF NOT EXISTS idx_company_websites_mbs_primary
  ON company_websites (mbs, is_primary DESC, score DESC NULLS LAST);

COMMENT ON COLUMN company_websites.is_primary IS 'Glavna (corporate) domena za MBS';
COMMENT ON COLUMN company_websites.role IS 'corporate | shop | booking | campaign | legacy | other';
