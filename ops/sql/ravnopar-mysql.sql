-- Ravnopar — korisni MySQL SELECT-ovi
-- Baza: MySQL (DATABASE_URL na VPS / Render)
-- Vault: ops/sql/
-- Schema: ravnopar/backend/prisma/schema.prisma
--
-- Na VPS-u (primjer):
--   mysql -u ravnopar -p ravnopar < ravnopar-mysql.sql
-- Ili preko Prisma Studio: cd ravnopar/backend && npx prisma studio

-- ========== PREGLED ==========
SELECT 'UserProfile' AS what, COUNT(*) AS n FROM UserProfile
UNION ALL SELECT 'MatchContact', COUNT(*) FROM MatchContact
UNION ALL SELECT 'EngagedPair', COUNT(*) FROM EngagedPair
UNION ALL SELECT 'PaymentOrder', COUNT(*) FROM PaymentOrder
UNION ALL SELECT 'UserReport', COUNT(*) FROM UserReport
UNION ALL SELECT 'AuditEvent', COUNT(*) FROM AuditEvent;

-- Po ulozi
SELECT role, COUNT(*) AS n
FROM UserProfile
GROUP BY role
ORDER BY n DESC;

-- Po dostupnosti
SELECT availability, COUNT(*) AS n
FROM UserProfile
GROUP BY availability
ORDER BY n DESC;

-- ========== KORISNICI ==========
-- Zadnji registrirani (prilagodi imena kolona ako schema drugačija)
SELECT id, email, role, availability, createdAt
FROM UserProfile
ORDER BY createdAt DESC
LIMIT 20;

-- Admini
SELECT id, email, createdAt
FROM UserProfile
WHERE role = 'ADMIN';

-- ========== MATCHMAKING ==========
SELECT status, COUNT(*) AS n
FROM MatchContact
GROUP BY status
ORDER BY n DESC;

SELECT status, COUNT(*) AS n
FROM EngagedPair
GROUP BY status;

-- Pending kontakti (zadnjih 24h — prilagodi)
SELECT id, requesterId, targetId, status, createdAt
FROM MatchContact
WHERE status = 'PENDING'
ORDER BY createdAt DESC
LIMIT 30;

-- Aktivni parovi
SELECT id, status, createdAt, updatedAt
FROM EngagedPair
WHERE status = 'ACTIVE'
ORDER BY updatedAt DESC
LIMIT 30;

-- ========== PLAĆANJA ==========
SELECT status, type, COUNT(*) AS n
FROM PaymentOrder
GROUP BY status, type
ORDER BY n DESC;

SELECT id, type, status, amount, currency, createdAt
FROM PaymentOrder
ORDER BY createdAt DESC
LIMIT 20;

-- ========== MODERACIJA ==========
SELECT status, COUNT(*) AS n
FROM UserReport
GROUP BY status;

SELECT id, reporterId, reportedId, status, createdAt
FROM UserReport
WHERE status IN ('OPEN', 'IN_REVIEW')
ORDER BY createdAt DESC
LIMIT 30;

-- ========== AUDIT ==========
SELECT category, COUNT(*) AS n
FROM AuditEvent
GROUP BY category
ORDER BY n DESC;

SELECT id, category, action, left(summary, 80) AS summary, createdAt
FROM AuditEvent
ORDER BY createdAt DESC
LIMIT 30;
