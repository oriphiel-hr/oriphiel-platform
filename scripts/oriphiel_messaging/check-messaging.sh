#!/usr/bin/env bash
# Provjera messaging baze + attachmenta na disku (pokreni NA VPS-u)
#
#   cd /root/oriphiel-ai/oriphiel_messaging
#   bash check-messaging.sh
#   ACCOUNT_EMAIL=mario.vitt@oriphiel.hr bash check-messaging.sh

set -euo pipefail

ACC="${ACCOUNT_EMAIL:-mario.vitt@oriphiel.hr}"
ATTACH="${ATTACH_DIR:-/var/lib/oriphiel/attachments}"
STATUS="${STATUS_FILE:-/tmp/oriphiel-imap-backfill-mario.vitt.json}"
PG="${PG_CONTAINER:-oriphiel-postgres}"
DB="${PG_DB:-oriphiel}"
USER="${PG_USER:-oriphiel}"

psql_q() {
  docker exec -i "$PG" psql -U "$USER" -d "$DB" -v ON_ERROR_STOP=1 "$@"
}

echo "=== Oriphiel Messaging CHECK (VPS) ==="
echo "account=$ACC"
echo

echo "=== BACKFILL STATUS ==="
if [[ -f "$STATUS" ]]; then
  cat "$STATUS"
  echo
else
  echo "(nema $STATUS)"
  ls -la /tmp/oriphiel-imap-backfill*.json 2>/dev/null || echo "(nema status json)"
fi
echo

echo "=== PROCESI ==="
pgrep -af 'sync-imap-backfill' || echo "(nema procesa)"
echo

echo "=== BAZA — brojevi ==="
psql_q -c "
SELECT 'accounts' AS what, count(*)::text AS n FROM channels_accounts
UNION ALL SELECT 'contacts', count(*)::text FROM contacts
UNION ALL SELECT 'messages', count(*)::text FROM messages
UNION ALL SELECT 'messages_with_ai', count(*)::text FROM messages
  WHERE ai_summary IS NOT NULL AND btrim(ai_summary) <> ''
UNION ALL SELECT 'attachments_db', count(*)::text FROM message_attachments;
"

echo "=== ACCOUNT + AI ==="
psql_q -c "
SELECT ca.id AS account_id, ca.address,
       count(m.id) AS messages,
       count(m.ai_summary) FILTER (
         WHERE m.ai_summary IS NOT NULL AND btrim(m.ai_summary) <> ''
       ) AS with_ai,
       count(a.id) AS attachments_db
FROM channels_accounts ca
LEFT JOIN messages m ON m.account_id = ca.id
LEFT JOIN message_attachments a ON a.message_id = m.id
WHERE lower(ca.address) = lower('$ACC')
GROUP BY ca.id, ca.address;
"

AID="$(docker exec -i "$PG" psql -U "$USER" -d "$DB" -Atc \
  "SELECT id FROM channels_accounts WHERE lower(address)=lower('$ACC') LIMIT 1;")"
echo "account_id=$AID"
echo

if [[ -z "$AID" ]]; then
  echo "Account nije u bazi — kraj."
  exit 0
fi

echo "=== ZADNJE PORUKE ==="
psql_q -c "
SELECT m.id, left(m.subject, 50) AS subject, m.ai_priority,
       left(coalesce(m.ai_summary,''), 50) AS ai_summary, m.received_at
FROM messages m
WHERE m.account_id = $AID
ORDER BY m.id DESC
LIMIT 8;
"

echo "=== DISK ==="
DIR="$ATTACH/email/$AID"
echo "dir=$DIR"
if [[ -d "$DIR" ]]; then
  echo -n "files="; find "$DIR" -type f | wc -l
  echo -n "size="; du -sh "$DIR" | cut -f1
  echo "--- najnovije datoteke ---"
  ls -lt "$DIR" | head -16
else
  echo "(direktorij ne postoji)"
  ls -la "$ATTACH/email/" 2>/dev/null || true
fi
echo

DBN="$(docker exec -i "$PG" psql -U "$USER" -d "$DB" -Atc \
  "SELECT count(*) FROM message_attachments ma
   JOIN messages m ON m.id=ma.message_id WHERE m.account_id=$AID;")"
DISK="$(find "$DIR" -type f 2>/dev/null | wc -l | tr -d ' ')"
echo "=== USPOREDBA ==="
echo "attachments_db=$DBN  files_on_disk=$DISK"
echo "Gotovo."
