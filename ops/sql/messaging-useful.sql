-- Oriphiel messaging — korisni SELECT-ovi
-- Baza: Postgres `oriphiel` (container oriphiel-postgres)
-- Vault: ops/sql/  |  Izvor (deploy): scripts/oriphiel_messaging/sql/useful-selects.sql
--
-- Na VPS-u:
--   docker exec -i oriphiel-postgres psql -U oriphiel -d oriphiel -f - < messaging-useful.sql
-- S Windowsa:
--   powershell -File scripts\oriphiel_messaging\Invoke-OriphielSql.ps1 -Sql "SELECT ..."

-- ========== PREGLED ==========
SELECT 'accounts' AS what, count(*)::text AS n FROM channels_accounts
UNION ALL SELECT 'contacts', count(*)::text FROM contacts
UNION ALL SELECT 'messages', count(*)::text FROM messages
UNION ALL SELECT 'messages_with_ai', count(*)::text FROM messages
  WHERE ai_summary IS NOT NULL AND btrim(ai_summary) <> ''
UNION ALL SELECT 'attachments_db', count(*)::text FROM message_attachments;

-- Po accountu
SELECT ca.id, ca.address, ca.is_active,
       count(m.id) AS messages,
       count(m.id) FILTER (WHERE m.ai_summary IS NOT NULL AND btrim(m.ai_summary) <> '') AS with_ai,
       count(a.id) AS attachments
FROM channels_accounts ca
LEFT JOIN messages m ON m.account_id = ca.id
LEFT JOIN message_attachments a ON a.message_id = m.id
GROUP BY ca.id, ca.address, ca.is_active
ORDER BY ca.id;

-- ========== PORUKE ==========
-- Zadnje poruke (mario.vitt)
SELECT m.id, left(m.subject, 60) AS subject, m.from_address,
       m.ai_priority, left(coalesce(m.ai_summary,''), 80) AS ai_summary,
       m.received_at
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = 'mario.vitt@oriphiel.hr'
ORDER BY m.received_at DESC NULLS LAST
LIMIT 20;

-- Po statusu
SELECT m.status, count(*) AS n
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = 'mario.vitt@oriphiel.hr'
GROUP BY m.status
ORDER BY n DESC;

-- Po AI prioritetu
SELECT coalesce(m.ai_priority,'(nema AI)') AS ai_priority, count(*) AS n
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = 'mario.vitt@oriphiel.hr'
GROUP BY m.ai_priority
ORDER BY n DESC;

-- Urgent / high
SELECT m.id, left(m.subject, 60) AS subject, m.ai_priority,
       left(m.ai_summary, 100) AS ai_summary, m.received_at
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = 'mario.vitt@oriphiel.hr'
  AND m.ai_priority IN ('urgent', 'high')
ORDER BY m.received_at DESC NULLS LAST
LIMIT 30;

-- Bez AI (još nije obogaćeno)
SELECT count(*) AS without_ai
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = 'mario.vitt@oriphiel.hr'
  AND (m.ai_summary IS NULL OR btrim(m.ai_summary) = '');

-- Threadovi s više poruka
SELECT m.thread_key, count(*) AS n,
       min(m.received_at) AS first_at, max(m.received_at) AS last_at,
       left(max(m.subject), 50) AS sample_subject
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = 'mario.vitt@oriphiel.hr'
  AND m.thread_key IS NOT NULL
GROUP BY m.thread_key
HAVING count(*) > 1
ORDER BY n DESC
LIMIT 20;

-- ========== ATTACHMENTI ==========
SELECT ma.id, ma.message_id, ma.filename, ma.mime_type, ma.size_bytes,
       ma.storage_path, m.subject
FROM message_attachments ma
JOIN messages m ON m.id = ma.message_id
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = 'mario.vitt@oriphiel.hr'
ORDER BY ma.id DESC
LIMIT 20;

SELECT count(*) AS attach_rows,
       count(DISTINCT ma.storage_path) AS distinct_paths,
       pg_size_pretty(coalesce(sum(ma.size_bytes),0)) AS sum_size
FROM message_attachments ma
JOIN messages m ON m.id = ma.message_id
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = 'mario.vitt@oriphiel.hr';

-- ========== KONTAKTI ==========
SELECT c.id, c.primary_email, c.name, count(m.id) AS messages
FROM contacts c
LEFT JOIN messages m ON m.contact_id = c.id
GROUP BY c.id, c.primary_email, c.name
ORDER BY messages DESC
LIMIT 30;

-- ========== AI DRAFT ==========
SELECT m.id, left(m.subject, 40) AS subject,
       left(m.ai_draft, 120) AS ai_draft
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = 'mario.vitt@oriphiel.hr'
  AND m.ai_draft IS NOT NULL AND btrim(m.ai_draft) <> ''
ORDER BY m.id DESC
LIMIT 10;
