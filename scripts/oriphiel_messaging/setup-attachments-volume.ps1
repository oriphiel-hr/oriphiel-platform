# Upload + pokreni setup-attachments-volume.sh na VPS-u
#   powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging\setup-attachments-volume.ps1

[CmdletBinding()]
param(
  [string]$SshTarget = "root@186.240.157.80"
)

$ErrorActionPreference = "Stop"
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Sh = Join-Path $scriptDir "setup-attachments-volume.sh"
if (-not (Test-Path -LiteralPath $Sh)) { throw "Nedostaje: $Sh" }

$raw = [System.IO.File]::ReadAllText($Sh) -replace "`r`n", "`n" -replace "`r", "`n"
$tmp = Join-Path $env:TEMP "setup-attachments-volume.sh"
[System.IO.File]::WriteAllText($tmp, $raw, (New-Object System.Text.UTF8Encoding $false))

scp $tmp "${SshTarget}:/tmp/setup-attachments-volume.sh"
ssh $SshTarget "sed -i 's/\r`$//' /tmp/setup-attachments-volume.sh; chmod +x /tmp/setup-attachments-volume.sh; bash /tmp/setup-attachments-volume.sh"