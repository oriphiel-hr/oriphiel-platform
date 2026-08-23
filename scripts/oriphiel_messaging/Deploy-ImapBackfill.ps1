# Upload IMAP backfill skripte na VPS (Ollama srv1890026)
#   powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging\Deploy-ImapBackfill.ps1

[CmdletBinding()]
param(
  [string]$SshTarget = "root@186.240.157.80",
  [string]$RemoteDir = "/root/oriphiel-ai/oriphiel_messaging"
)

$ErrorActionPreference = "Stop"
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

function Write-UnixFile([string]$SourcePath, [string]$DestPath) {
  $raw = [System.IO.File]::ReadAllText($SourcePath)
  $raw = $raw -replace "`r`n", "`n" -replace "`r", "`n"
  [System.IO.File]::WriteAllText($DestPath, $raw, (New-Object System.Text.UTF8Encoding $false))
}

$files = @(
  "sync-imap-backfill.py",
  "sync-imap-backfill.sh",
  "sync-imap-backfill-all.sh",
  "ollama-enrich-message.py",
  "enrich-existing-messages.py",
  "run-backfill-mario.vitt.sh",
  "check-messaging.sh",
  "Check-OriphielMessaging.ps1",
  "imap-backfill.env.example"
)

ssh $SshTarget "mkdir -p $RemoteDir/accounts $RemoteDir/sql"
foreach ($f in $files) {
  $src = Join-Path $scriptDir $f
  if (-not (Test-Path -LiteralPath $src)) { throw "Nedostaje: $src" }
  $tmp = Join-Path $env:TEMP $f
  Write-UnixFile -SourcePath $src -DestPath $tmp
  scp $tmp "${SshTarget}:$RemoteDir/$f"
}

$sqlExtra = @(
  @{ Local = "sql\oriphiel-messaging-schema.sql"; Remote = "sql/oriphiel-messaging-schema.sql" },
  @{ Local = "sql\useful-selects.sql"; Remote = "sql/useful-selects.sql" },
  @{ Local = "sql\message-attachments.sql"; Remote = "sql/message-attachments.sql" }
)
foreach ($e in $sqlExtra) {
  $src = Join-Path $scriptDir $e.Local
  if (Test-Path -LiteralPath $src) {
    $tmp = Join-Path $env:TEMP ([IO.Path]::GetFileName($e.Remote))
    Write-UnixFile -SourcePath $src -DestPath $tmp
    scp $tmp "${SshTarget}:$RemoteDir/$($e.Remote)"
    Write-Host "  + $($e.Remote)"
  }
}

$examples = @(
  @{ Local = "accounts\oriphiel.hr-mario.vitt.env.example"; Remote = "accounts/oriphiel.hr-mario.vitt.env.example" },
  @{ Local = "accounts\info.env.example"; Remote = "accounts/info.env.example" }
)
foreach ($e in $examples) {
  $src = Join-Path $scriptDir $e.Local
  if (Test-Path -LiteralPath $src) {
    $tmp = Join-Path $env:TEMP ([IO.Path]::GetFileName($e.Remote))
    Write-UnixFile -SourcePath $src -DestPath $tmp
    scp $tmp "${SshTarget}:$RemoteDir/$($e.Remote)"
  }
}

ssh $SshTarget @"
chmod +x $RemoteDir/sync-imap-backfill.sh $RemoteDir/sync-imap-backfill-all.sh $RemoteDir/sync-imap-backfill.py $RemoteDir/run-backfill-mario.vitt.sh $RemoteDir/check-messaging.sh
sed -i 's/\r`$//' $RemoteDir/sync-imap-backfill.sh $RemoteDir/sync-imap-backfill-all.sh $RemoteDir/sync-imap-backfill.py $RemoteDir/run-backfill-mario.vitt.sh $RemoteDir/check-messaging.sh
"@
Write-Host ""
Write-Host "Upload OK -> $RemoteDir" -ForegroundColor Green
Write-Host ""
Write-Host "Prvi put na VPS-u:"
Write-Host "  cp $RemoteDir/accounts/oriphiel.hr-mario.vitt.env.example $RemoteDir/accounts/oriphiel.hr-mario.vitt.env"
Write-Host "  nano $RemoteDir/accounts/oriphiel.hr-mario.vitt.env   # IMAP_PASSWORD"
Write-Host ""
Write-Host "Backfill:"
Write-Host "  bash $RemoteDir/run-backfill-mario.vitt.sh"
Write-Host ""
Write-Host "Status:"
Write-Host "  watch -n2 cat /tmp/oriphiel-imap-backfill-mario.vitt.json"
Write-Host ""
Write-Host "Provjera baze + disk:"
Write-Host "  bash $RemoteDir/check-messaging.sh"
Write-Host ""
Write-Host "n8n (Downloads, ne ovaj deploy):"
Write-Host "  Oriphiel-Live-Account-Stub.json  — live IMAP+AI"
Write-Host "  Oriphiel-Mail-Hub.json           — backfill/enrich/count"
Write-Host "  (New mails - mario.vitt… = DEPRECATED)"
