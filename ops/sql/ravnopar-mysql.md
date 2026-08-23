# Ad-hoc SQL — Ravnopar (MySQL)

Host: **srv1889799** (`186.240.157.39`) · baza `ravnopar`

---

## Gdje si? (obavezno `cd`)

| Okolina | Direktorij |
|---------|------------|
| **Windows (kod)** | `C:\GIT_PROJEKTI\oriphiel-platform\ravnopar` |
| **VPS (SSH bash)** | `/var/www/Render/ravnopar` |
| Backend (VPS) | `/var/www/Render/ravnopar/backend` |

> Lozinka/user baze → **Bitwarden**

---

## VPS — bash (preporučeno u SSH sesiji)

```bash
ssh root@186.240.157.39
cd /var/www/Render/ravnopar
```

```bash
mysql -u ravnopar -p ravnopar -e "
SELECT COUNT(*) FROM UserProfile;
"
```

---

## Windows — PowerShell + `@"` (preko SSH)

```powershell
$Ssh = "root@186.240.157.39"
$Sql = @"
SELECT COUNT(*) AS n FROM UserProfile;
"@
ssh $Ssh "mysql -N -e `"$($Sql -replace '"','\"' -replace "`r?`n",' ')`" ravnopar"
```

Batch: [`ravnopar-mysql.sql`](ravnopar-mysql.sql)

---

## Pregled

```powershell
$Sql = @"
SELECT 'UserProfile' AS what, COUNT(*) AS n FROM UserProfile
UNION ALL SELECT 'MatchContact', COUNT(*) FROM MatchContact
UNION ALL SELECT 'EngagedPair', COUNT(*) FROM EngagedPair
UNION ALL SELECT 'PaymentOrder', COUNT(*) FROM PaymentOrder
UNION ALL SELECT 'UserReport', COUNT(*) FROM UserReport
UNION ALL SELECT 'AuditEvent', COUNT(*) FROM AuditEvent;
"@
```

```powershell
$Sql = @"
SELECT role, COUNT(*) AS n
FROM UserProfile
GROUP BY role
ORDER BY n DESC;
"@
```

```powershell
$Sql = @"
SELECT availability, COUNT(*) AS n
FROM UserProfile
GROUP BY availability
ORDER BY n DESC;
"@
```

---

## Korisnici

```powershell
$Sql = @"
SELECT id, email, role, availability, createdAt
FROM UserProfile
ORDER BY createdAt DESC
LIMIT 20;
"@
```

```powershell
$Sql = @"
SELECT id, email, createdAt
FROM UserProfile
WHERE role = 'ADMIN';
"@
```

---

## Matchmaking

```powershell
$Sql = @"
SELECT status, COUNT(*) AS n
FROM MatchContact
GROUP BY status
ORDER BY n DESC;
"@
```

```powershell
$Sql = @"
SELECT status, COUNT(*) AS n
FROM EngagedPair
GROUP BY status;
"@
```

```powershell
$Sql = @"
SELECT id, requesterId, targetId, status, createdAt
FROM MatchContact
WHERE status = 'PENDING'
ORDER BY createdAt DESC
LIMIT 30;
"@
```

```powershell
$Sql = @"
SELECT id, status, createdAt, updatedAt
FROM EngagedPair
WHERE status = 'ACTIVE'
ORDER BY updatedAt DESC
LIMIT 30;
"@
```

---

## Plaćanja / moderacija / audit

```powershell
$Sql = @"
SELECT status, type, COUNT(*) AS n
FROM PaymentOrder
GROUP BY status, type
ORDER BY n DESC;
"@
```

```powershell
$Sql = @"
SELECT id, type, status, amount, currency, createdAt
FROM PaymentOrder
ORDER BY createdAt DESC
LIMIT 20;
"@
```

```powershell
$Sql = @"
SELECT status, COUNT(*) AS n
FROM UserReport
GROUP BY status;
"@
```

```powershell
$Sql = @"
SELECT id, reporterId, reportedId, status, createdAt
FROM UserReport
WHERE status IN ('OPEN', 'IN_REVIEW')
ORDER BY createdAt DESC
LIMIT 30;
"@
```

```powershell
$Sql = @"
SELECT category, COUNT(*) AS n
FROM AuditEvent
GROUP BY category
ORDER BY n DESC;
"@
```

```powershell
$Sql = @"
SELECT id, category, action, LEFT(summary, 80) AS summary, createdAt
FROM AuditEvent
ORDER BY createdAt DESC
LIMIT 30;
"@
```

---

## Na VPS-u (isti SQL, mysql CLI)

```bash
mysql -u ravnopar -p ravnopar -e "
SELECT COUNT(*) FROM UserProfile;
"
```
