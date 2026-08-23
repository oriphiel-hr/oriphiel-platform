# Provjera Oriphiel messaging: baza + attachmenti na disku + backfill status
#
# S Windowsa (SSH):
#   powershell -ExecutionPolicy Bypass -File .\Check-OriphielMessaging.ps1
#   powershell -ExecutionPolicy Bypass -File .\Check-OriphielMessaging.ps1 -AccountEmail mario.vitt@oriphiel.hr
#
# Na VPS-u (isti stroj):
#   powershell -ExecutionPolicy Bypass -File .\Check-OriphielMessaging.ps1 -Local
#   # ili: bash check-messaging.sh

[CmdletBinding()]
param(
  [string]$SshTarget = "root@186.240.157.80",
  [string]$PgContainer = "oriphiel-postgres",
  [string]$DbName = "oriphiel",
  [string]$DbUser = "oriphiel",
  [string]$AccountEmail = "mario.vitt@oriphiel.hr",
  [string]$AttachRoot = "/var/lib/oriphiel/attachments",
  [string]$StatusFile = "/tmp/oriphiel-imap-backfill-mario.vitt.json",
  [switch]$Local,
  [switch]$RunUsefulSql,
  [switch]$AsJson
)

$ErrorActionPreference = "Stop"
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

$useLocal = $Local -or ($env:ORIPHIEL_LOCAL -eq "1") -or $IsLinux -or $IsMacOS

function Invoke-RemoteBash([string]$Cmd) {
  if ($useLocal) {
    bash -lc $Cmd
  } else {
    ssh -o BatchMode=yes -o ConnectTimeout=15 $SshTarget $Cmd
  }
}

$sql = @"
\pset border 2
\pset format aligned
SELECT 'accounts' AS what, count(*)::text AS n FROM channels_accounts
UNION ALL SELECT 'contacts', count(*)::text FROM contacts
UNION ALL SELECT 'messages', count(*)::text FROM messages
UNION ALL SELECT 'messages_with_ai', count(*)::text FROM messages WHERE ai_summary IS NOT NULL AND btrim(ai_summary) <> ''
UNION ALL SELECT 'attachments_db', count(*)::text FROM message_attachments;

SELECT ca.id AS account_id, ca.address,
       count(m.id) AS messages,
       count(m.ai_summary) FILTER (WHERE m.ai_summary IS NOT NULL AND btrim(m.ai_summary) <> '') AS with_ai,
       count(a.id) AS attachments_db
FROM channels_accounts ca
LEFT JOIN messages m ON m.account_id = ca.id
LEFT JOIN message_attachments a ON a.message_id = m.id
WHERE lower(ca.address) = lower('$AccountEmail')
GROUP BY ca.id, ca.address;

SELECT status, count(*) AS n
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = lower('$AccountEmail')
GROUP BY status
ORDER BY n DESC;

SELECT ai_priority, count(*) AS n
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = lower('$AccountEmail')
  AND m.ai_priority IS NOT NULL
GROUP BY ai_priority
ORDER BY n DESC;

SELECT m.id, left(m.subject, 50) AS subject, m.ai_priority,
       left(coalesce(m.ai_summary,''), 60) AS ai_summary,
       m.received_at
FROM messages m
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = lower('$AccountEmail')
ORDER BY m.id DESC
LIMIT 8;

SELECT ma.id, ma.message_id, left(ma.filename, 40) AS filename,
       ma.size_bytes, left(ma.storage_path, 80) AS storage_path
FROM message_attachments ma
JOIN messages m ON m.id = ma.message_id
JOIN channels_accounts ca ON ca.id = m.account_id
WHERE lower(ca.address) = lower('$AccountEmail')
ORDER BY ma.id DESC
LIMIT 10;
"@

$bash = @"
set -e
ACC='$AccountEmail'
ATTACH='$AttachRoot'
STATUS='$StatusFile'
PG='$PgContainer'
DB='$DbName'
USER='$DbUser'

echo '=== BACKFILL STATUS JSON ==='
if [ -f "`$STATUS" ]; then
  cat "`$STATUS"
  echo
else
  echo "(nema `$STATUS — backfill nije pokrenut s tim STATUS_FILE)"
  ls -la /tmp/oriphiel-imap-backfill*.json 2>/dev/null || echo '(nema /tmp/oriphiel-imap-backfill*.json)'
fi
echo

echo '=== PROCESI ==='
pgrep -af 'sync-imap-backfill' || echo '(nema sync-imap-backfill procesa)'
echo

echo '=== ACCOUNT ID ==='
AID=`$(docker exec -i `$PG psql -U `$USER -d `$DB -Atc "SELECT id FROM channels_accounts WHERE lower(address)=lower('`$ACC') LIMIT 1;")
echo "account_id=`$AID  email=`$ACC"
if [ -z "`$AID" ]; then
  echo 'Account nije u bazi.'
  exit 0
fi
echo

echo '=== DISK ATTACHMENTI ==='
DIR="`$ATTACH/email/`$AID"
echo "dir=`$DIR"
if [ -d "`$DIR" ]; then
  echo -n 'files='; find "`$DIR" -type f | wc -l
  echo -n 'bytes='; du -sb "`$DIR" 2>/dev/null | cut -f1
  echo '--- top 15 files (najnovije) ---'
  ls -lt "`$DIR" 2>/dev/null | head -16
else
  echo '(direktorij ne postoji)'
  ls -la "`$ATTACH/email/" 2>/dev/null || ls -la "`$ATTACH/" 2>/dev/null || true
fi
echo

echo '=== USPOREDBA DB vs DISK ==='
DBN=`$(docker exec -i `$PG psql -U `$USER -d `$DB -Atc "SELECT count(*) FROM message_attachments ma JOIN messages m ON m.id=ma.message_id WHERE m.account_id=`$AID;")
DISK=`$(find "`$DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
echo "attachments_db=`$DBN  files_on_disk=`$DISK"
"@

Write-Host "=== Oriphiel Messaging CHECK ===" -ForegroundColor Cyan
Write-Host ("mode={0} target={1} account={2}" -f ($(if ($useLocal) { "Local" } else { "SSH" }), $SshTarget, $AccountEmail))
Write-Host ""

Write-Host "=== BAZA (Postgres) ===" -ForegroundColor DarkCyan
$tmp = Join-Path $env:TEMP ("oriphiel-check-{0}.sql" -f [guid]::NewGuid().ToString("N"))
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($tmp, ($sql -replace "`r`n", "`n"), $utf8)
try {
  if ($useLocal) {
    Get-Content -LiteralPath $tmp -Raw -Encoding UTF8 |
      docker exec -i $PgContainer psql -U $DbUser -d $DbName -v ON_ERROR_STOP=1
  } else {
    scp $tmp "${SshTarget}:/tmp/oriphiel-check.sql" | Out-Null
    ssh $SshTarget "sed -i 's/\r`$//' /tmp/oriphiel-check.sql; cat /tmp/oriphiel-check.sql | docker exec -i $PgContainer psql -U $DbUser -d $DbName -v ON_ERROR_STOP=1"
  }
} finally {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== DISK + BACKFILL (remote) ===" -ForegroundColor DarkCyan
$bashUnix = ($bash -replace "`r`n", "`n" -replace "`r", "`n")
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bashUnix))
Invoke-RemoteBash "echo $b64 | base64 -d | bash"

Write-Host ""
Write-Host "Gotovo. Za SQL ad-hoc: Invoke-OriphielSql.ps1 -Sql `"SELECT ...`"" -ForegroundColor DarkGray
Write-Host "Svi korisni SELECT-ovi: Check-OriphielMessaging.ps1 -RunUsefulSql" -ForegroundColor DarkGray
Write-Host "Datoteka: sql/useful-selects.sql" -ForegroundColor DarkGray

if ($RunUsefulSql) {
  Write-Host ""
  Write-Host "=== sql/useful-selects.sql ===" -ForegroundColor DarkCyan
  $sqlFile = Join-Path (Join-Path $scriptDir "sql") "useful-selects.sql"
  if (-not (Test-Path -LiteralPath $sqlFile)) { throw "Nedostaje: $sqlFile" }
  $sqlAll = Get-Content -LiteralPath $sqlFile -Raw -Encoding UTF8
  $tmp2 = Join-Path $env:TEMP ("oriphiel-useful-{0}.sql" -f [guid]::NewGuid().ToString("N"))
  [System.IO.File]::WriteAllText($tmp2, ($sqlAll -replace "`r`n", "`n"), $utf8)
  try {
    if ($useLocal) {
      Get-Content -LiteralPath $tmp2 -Raw -Encoding UTF8 |
        docker exec -i $PgContainer psql -U $DbUser -d $DbName -v ON_ERROR_STOP=1
    } else {
      scp $tmp2 "${SshTarget}:/tmp/oriphiel-useful.sql" | Out-Null
      ssh $SshTarget "sed -i 's/\r`$//' /tmp/oriphiel-useful.sql; cat /tmp/oriphiel-useful.sql | docker exec -i $PgContainer psql -U $DbUser -d $DbName -v ON_ERROR_STOP=1"
    }
  } finally {
    Remove-Item -LiteralPath $tmp2 -Force -ErrorAction SilentlyContinue
  }
}