-- Folder / labels / soft-delete za messages
-- Pokreni: cat sql/migrate-messages-folder-labels.sql | docker exec -i oriphiel-postgres psql -U oriphiel -d oriphiel

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS folder TEXT,
  ADD COLUMN IF NOT EXISTS imap_uid BIGINT,
  ADD COLUMN IF NOT EXISTS labels TEXT[] NOT NULL DEFAULT '{}'::text[],
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

COMMENT ON COLUMN messages.folder IS 'IMAP mailbox npr. INBOX, Sent, Archive';
COMMENT ON COLUMN messages.imap_uid IS 'UID unutar folder-a (folder-scoped)';
COMMENT ON COLUMN messages.labels IS 'IMAP FLAGS + KEYWORDS + X-GM-LABELS (ako postoje)';
COMMENT ON COLUMN messages.deleted_at IS 'Soft-delete kad UID nestane s servera; NULL = aktivan';

CREATE INDEX IF NOT EXISTS idx_messages_folder
  ON messages (account_id, folder, received_at DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_messages_imap_uid
  ON messages (account_id, folder, imap_uid)
  WHERE imap_uid IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_messages_deleted
  ON messages (account_id, deleted_at)
  WHERE deleted_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_messages_labels_gin
  ON messages USING GIN (labels);

-- Aktivni mailovi (UI filter)
-- SELECT * FROM messages WHERE deleted_at IS NULL AND folder = 'INBOX';
