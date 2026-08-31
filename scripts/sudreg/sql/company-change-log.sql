-- Log stvarnih izmjena polja koja pratimo (ne Sudreg /promjene API signal)

CREATE TABLE IF NOT EXISTS company_change_log (
  id           BIGSERIAL PRIMARY KEY,
  mbs          TEXT NOT NULL REFERENCES companies(mbs) ON DELETE CASCADE,
  field_name   TEXT NOT NULL,
  old_value    TEXT,
  new_value    TEXT,
  snapshot_id  BIGINT,
  source       TEXT NOT NULL DEFAULT 'sync',
  changed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_company_change_log_mbs_time
  ON company_change_log (mbs, changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_company_change_log_time
  ON company_change_log (changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_company_change_log_field
  ON company_change_log (field_name);

ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS data_changed_at TIMESTAMPTZ;

COMMENT ON COLUMN companies.updated_at IS 'Zadnji sync/touch (može bez stvarne izmjene sadržaja)';
COMMENT ON COLUMN companies.data_changed_at IS 'Zadnja stvarna izmjena praćenog polja';
COMMENT ON TABLE company_change_log IS 'Diff praćenih polja; /promjene API samo signalira da je nešto na Sudregu, ne i što pratimo';

CREATE OR REPLACE FUNCTION sudreg_log_company_row_changes()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  fields text[] := ARRAY[
    'oib','euid','status','deleted','deleted_note','nadlezni_sud',
    'naziv','naziv_kraci','adresa','email','website',
    'temeljni_kapital','pravni_oblik','pretezita_djelatnost'
  ];
  f text;
  old_v text;
  new_v text;
  any_change boolean := false;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    FOREACH f IN ARRAY fields LOOP
      EXECUTE format('SELECT ($1).%I::text, ($2).%I::text', f, f)
        INTO old_v, new_v
        USING OLD, NEW;
      IF old_v IS DISTINCT FROM new_v THEN
        any_change := true;
        INSERT INTO company_change_log (mbs, field_name, old_value, new_value, snapshot_id, source)
        VALUES (
          NEW.mbs,
          f,
          left(old_v, 4000),
          left(new_v, 4000),
          NEW.snapshot_id,
          COALESCE(nullif(current_setting('sudreg.change_source', true), ''), 'sync')
        );
      END IF;
    END LOOP;
    IF any_change THEN
      NEW.data_changed_at := NOW();
    ELSIF NEW.data_changed_at IS NULL AND OLD.data_changed_at IS NOT NULL THEN
      NEW.data_changed_at := OLD.data_changed_at;
    END IF;
  ELSIF TG_OP = 'INSERT' THEN
    NEW.data_changed_at := COALESCE(NEW.data_changed_at, NOW());
    INSERT INTO company_change_log (mbs, field_name, old_value, new_value, snapshot_id, source)
    VALUES (
      NEW.mbs, '_created', NULL, left(COALESCE(NEW.naziv, NEW.mbs), 4000), NEW.snapshot_id,
      COALESCE(nullif(current_setting('sudreg.change_source', true), ''), 'sync')
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_companies_change_log ON companies;
CREATE TRIGGER trg_companies_change_log
  BEFORE INSERT OR UPDATE ON companies
  FOR EACH ROW
  EXECUTE FUNCTION sudreg_log_company_row_changes();

-- Helper: log child-collection fingerprint (activities / people / …)
CREATE OR REPLACE FUNCTION sudreg_log_collection_change(
  p_mbs text,
  p_field text,
  p_old text,
  p_new text,
  p_snapshot_id bigint DEFAULT NULL,
  p_source text DEFAULT 'sync'
) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_old IS DISTINCT FROM p_new THEN
    INSERT INTO company_change_log (mbs, field_name, old_value, new_value, snapshot_id, source)
    VALUES (p_mbs, p_field, left(p_old, 4000), left(p_new, 4000), p_snapshot_id, p_source);
    UPDATE companies
    SET data_changed_at = NOW()
    WHERE mbs = p_mbs;
  END IF;
END;
$$;
