# Ad-hoc SQL na bazi oriphiel (VPS Postgres)
#
# Primjeri:
#   powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging\Invoke-OriphielSql.ps1
#   powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging\Invoke-OriphielSql.ps1 -Sql "SELECT id, address FROM channels_accounts ORDER BY id;"

[CmdletBinding()]
param(
  [string]$SshTarget = "root@186.240.157.80",
  [string]$PgContainer = "oriphiel-postgres",
  [string]$DbName = "oriphiel",
  [string]$DbUser = "oriphiel",
  [string]$Sql = @"
SELECT id AS account_id
FROM channels_accounts
WHERE address = 'mario.vitt@oriphiel.hr'
LIMIT 1;
"@
)

$ErrorActionPreference = "Stop"

$tmp = Join-Path $env:TEMP ("oriphiel-adhoc-{0}.sql" -f [guid]::NewGuid().ToString("N"))
$raw = ($Sql -replace "`r`n", "`n" -replace "`r", "`n").Trim() + "`n"
[System.IO.File]::WriteAllText($tmp, $raw, (New-Object System.Text.UTF8Encoding $false))

try {
  scp $tmp "${SshTarget}:/tmp/oriphiel-adhoc.sql" | Out-Null
  ssh $SshTarget "sed -i 's/\r`$//' /tmp/oriphiel-adhoc.sql; cat /tmp/oriphiel-adhoc.sql | docker exec -i $PgContainer psql -U $DbUser -d $DbName -v ON_ERROR_STOP=1"
}
finally {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}