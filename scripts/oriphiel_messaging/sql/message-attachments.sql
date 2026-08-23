-- message_attachments (baza oriphiel)
-- Metadata u Postgresu; same datoteke drzi na disku/S3 (storage_path)

CREATE TABLE IF NOT EXISTS message_attachments (
  id              BIGSERIAL PRIMARY KEY,
  message_id      BIGINT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  filename        TEXT NOT NULL,
  mime_type       TEXT,
  size_bytes      BIGINT,
  storage_path    TEXT NOT NULL,
  sha256          TEXT,
  content_id      TEXT,
  is_inline       BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_attachments_message
  ON message_attachments (message_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_attachments_sha_per_message
  ON message_attachments (message_id, sha256)
  WHERE sha256 IS NOT NULL;