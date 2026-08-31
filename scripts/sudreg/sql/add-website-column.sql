-- Dodaj website kolonu (idempotentno)
ALTER TABLE companies ADD COLUMN IF NOT EXISTS website TEXT;
CREATE INDEX IF NOT EXISTS idx_companies_website ON companies (website);
