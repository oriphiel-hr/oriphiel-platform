-- Oriphiel messaging (baza: oriphiel) — scripts/oriphiel_messaging
-- Tablice: channels_accounts, contacts, messages (mail + kasnije Facebook)
-- Sudreg NIJE ovdje — ide u zasebnu bazu "sudreg"

CREATE TABLE IF NOT EXISTS channels_accounts (
  id            SERIAL PRIMARY KEY,
  name          TEXT NOT NULL,
  account_key   TEXT NOT NULL UNIQUE,
  channel       TEXT NOT NULL,
  address       TEXT,
  provider      TEXT,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  meta          JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS contacts (
  id            SERIAL PRIMARY KEY,
  name          TEXT,
  primary_email TEXT,
  phone         TEXT,
  facebook_psid TEXT,
  notes         TEXT,
  meta          JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_contacts_primary_email
  ON contacts (primary_email) WHERE primary_email IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_contacts_facebook_psid
  ON contacts (facebook_psid) WHERE facebook_psid IS NOT NULL;

CREATE TABLE IF NOT EXISTS messages (
  id              BIGSERIAL PRIMARY KEY,
  account_id      INT REFERENCES channels_accounts(id),
  contact_id      INT REFERENCES contacts(id),
  channel         TEXT NOT NULL,
  direction       TEXT NOT NULL CHECK (direction IN ('in', 'out')),
  from_address    TEXT,
  to_addresses    TEXT[],
  cc_addresses    TEXT[],
  subject         TEXT,
  body_text       TEXT,
  body_html       TEXT,
  external_id     TEXT,
  thread_key      TEXT,
  status          TEXT NOT NULL DEFAULT 'new',
  ai_summary      TEXT,
  ai_draft        TEXT,
  ai_priority     TEXT,
  raw             JSONB NOT NULL DEFAULT '{}'::jsonb,
  received_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (channel, external_id)
);

CREATE INDEX IF NOT EXISTS idx_messages_contact ON messages (contact_id, received_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_messages_account ON messages (account_id, received_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_messages_status  ON messages (status);
CREATE INDEX IF NOT EXISTS idx_messages_thread  ON messages (thread_key);
CREATE INDEX IF NOT EXISTS idx_messages_channel ON messages (channel, created_at DESC);

-- Attachments: metadata u Postgresu, datoteke na disku/S3 (storage_path)
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

CREATE INDEX IF NOT EXISTS idx_attachments_message ON message_attachments (message_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_attachments_sha_per_message
  ON message_attachments (message_id, sha256) WHERE sha256 IS NOT NULL;

INSERT INTO channels_accounts (name, account_key, channel, address, provider)
VALUES
  ('Info mailbox', 'email_info', 'email', 'info@oriphiel.hr', 'imap'),
  ('Ads mailbox',  'email_ads',  'email', 'ads@oriphiel.hr',  'imap'),
  ('Facebook Page','facebook_page', 'facebook', NULL, 'meta')
ON CONFLICT (account_key) DO NOTHING;
