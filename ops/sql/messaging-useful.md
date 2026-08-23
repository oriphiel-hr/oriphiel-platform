# Ad-hoc SQL — Messaging (Postgres `oriphiel`)

Host: **srv1890026** (`186.240.157.80`) · container `oriphiel-postgres` · baza `oriphiel`

---

## Gdje si? (obavezno `cd`)

| Okolina | Direktorij |
|---------|------------|
| **Windows** | `C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging` |
| **VPS (SSH bash)** | `/root/oriphiel-ai/oriphiel_messaging` |
| SQL batch (VPS) | `/root/oriphiel-ai/oriphiel_messaging/sql/useful-selects.sql` |

---

## VPS — bash (preporučeno u SSH sesiji)

```bash
ssh root@186.240.157.80
cd /root/oriphiel-ai/oriphiel_messaging
```

```bash
docker exec -i oriphiel-postgres psql -U oriphiel -d oriphiel -c "
SELECT count(*) FROM messages;
"
```

```bash
docker exec -i oriphiel-postgres psql -U oriphiel -d oriphiel -f - < sql/useful-selects.sql
bash check-messaging.sh
pwsh -File ./Check-OriphielMessaging.ps1 -Local
```

---

## Windows — PowerShell + `@"` … `"@`

```powershell
cd C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging
```

**Pokretanje:** `Invoke-OriphielSql.ps1 -Sql @" ... "@`

Batch: [`messaging-useful.sql`](messaging-useful.sql)

---

## Pregled

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-OriphielSql.ps1 -Sql @"
SELECT 'accounts' AS what, count(*)::text AS n FROM channels_accounts
UNION ALL SELECT 'contacts', count(*)::text FROM contacts
UNION ALL SELECT 'messages', count(*)::text FROM messages
UNION ALL SELECT 'messages_with_ai', count(*)::text FROM messages
  WHERE ai_summary IS NOT NULL AND btrim(ai_summary) <> ''
UNION ALL SELECT 'attachments_db', count(*)::text FROM message_attachments;
"@
```

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-OriphielSql.ps1 -Sql @"
SELECT ca.id, ca.address, ca.is_active,
       count(m.id) AS messages,
       count(m.id) FILTER (WHERE m.ai_summary IS NOT NULL AND btrim(m.ai_summary) <> '') AS with_ai,
       count(a.id) AS attachments
FROM channels_accounts ca
LEFT JOIN messages m ON m.account_id = ca.id
LEFT JOIN message_attachments a ON a.message_id = m.id
GROUP BY ca.id, ca.address, ca.is_active
ORDER BY ca.id;
"@
```

---

## Poruke (zamijeni email po potrebi)

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-OriphielSql.ps1 -Sql @"
SELECT m.id, left(m.subject, 60) AS subject, m.from_address,
       m.ai_priority, left(coalesce(m.ai_summary,''), 80) AS ai_summary,
       m.received_at
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = 'mario.vitt@oriphiel.hr'
ORDER BY m.received_at DESC NULLS LAST
LIMIT 20;
"@
```

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-OriphielSql.ps1 -Sql @"
SELECT m.status, count(*) AS n
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = 'mario.vitt@oriphiel.hr'
GROUP BY m.status
ORDER BY n DESC;
"@
```

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-OriphielSql.ps1 -Sql @"
SELECT coalesce(m.ai_priority,'(nema AI)') AS ai_priority, count(*) AS n
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = 'mario.vitt@oriphiel.hr'
GROUP BY m.ai_priority
ORDER BY n DESC;
"@
```

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-OriphielSql.ps1 -Sql @"
SELECT m.id, left(m.subject, 60) AS subject, m.ai_priority,
       left(m.ai_summary, 100) AS ai_summary, m.received_at
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = 'mario.vitt@oriphiel.hr'
  AND m.ai_priority IN ('urgent', 'high')
ORDER BY m.received_at DESC NULLS LAST
LIMIT 30;
"@
```

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-OriphielSql.ps1 -Sql @"
SELECT count(*) AS without_ai
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = 'mario.vitt@oriphiel.hr'
  AND (m.ai_summary IS NULL OR btrim(m.ai_summary) = '');
"@
```

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-OriphielSql.ps1 -Sql @"
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
"@
```

---

## Attachmenti / kontakti / AI draft

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-OriphielSql.ps1 -Sql @"
SELECT ma.id, ma.message_id, ma.filename, ma.mime_type, ma.size_bytes,
       ma.storage_path, m.subject
FROM message_attachments ma
JOIN messages m ON m.id = ma.message_id
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = 'mario.vitt@oriphiel.hr'
ORDER BY ma.id DESC
LIMIT 20;
"@
```

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-OriphielSql.ps1 -Sql @"
SELECT c.id, c.primary_email, c.name, count(m.id) AS messages
FROM contacts c
LEFT JOIN messages m ON m.contact_id = c.id
GROUP BY c.id, c.primary_email, c.name
ORDER BY messages DESC
LIMIT 30;
"@
```

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-OriphielSql.ps1 -Sql @"
SELECT m.id, left(m.subject, 40) AS subject,
       left(m.ai_draft, 120) AS ai_draft
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = 'mario.vitt@oriphiel.hr'
  AND m.ai_draft IS NOT NULL AND btrim(m.ai_draft) <> ''
ORDER BY m.id DESC
LIMIT 10;
"@
```

---

## Na VPS-u (isti SQL, bash)

```bash
docker exec -i oriphiel-postgres psql -U oriphiel -d oriphiel -c "
SELECT count(*) FROM messages;
"
```
