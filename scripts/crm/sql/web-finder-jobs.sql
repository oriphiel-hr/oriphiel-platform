-- Web finder background jobs (CRM)

CREATE TABLE IF NOT EXISTS web_finder_jobs (
  id              BIGSERIAL PRIMARY KEY,
  status          TEXT NOT NULL DEFAULT 'queued',
  -- queued | running | paused | done | failed
  started_by      TEXT,
  only_with_email BOOLEAN NOT NULL DEFAULT TRUE,
  auto_save_min_score INTEGER NOT NULL DEFAULT 60,
  max_companies   INTEGER,           -- NULL = bez limita (dok traje)
  sleep_seconds   NUMERIC(6,2) NOT NULL DEFAULT 4,
  processed       INTEGER NOT NULL DEFAULT 0,
  saved           INTEGER NOT NULL DEFAULT 0,
  skipped         INTEGER NOT NULL DEFAULT 0,
  errors          INTEGER NOT NULL DEFAULT 0,
  last_mbs        TEXT,
  last_message    TEXT,
  error_text      TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at      TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_web_finder_jobs_status ON web_finder_jobs (status);

CREATE TABLE IF NOT EXISTS web_finder_attempts (
  mbs           TEXT PRIMARY KEY,
  oib           TEXT,
  status        TEXT NOT NULL,
  -- saved | none | error | low_score
  website       TEXT,
  score         INTEGER,
  confidence    TEXT,
  detail        TEXT,
  job_id        BIGINT REFERENCES web_finder_jobs(id) ON DELETE SET NULL,
  attempted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_web_finder_attempts_at ON web_finder_attempts (attempted_at DESC);

COMMENT ON TABLE web_finder_jobs IS 'Masovna pozadinska pretraga weba (VPS worker)';
COMMENT ON TABLE web_finder_attempts IS 'Što je worker već probao — da ne vrti u krug';
