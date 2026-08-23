# Oriphiel AI — samo ugasi tools na VPS (branding vec mora biti na /opt/open-webui/branding)
$ErrorActionPreference = "Stop"
$VPS = "root@186.240.157.80"
$Script = Join-Path $PSScriptRoot "disable-tools.sh"

Write-Host "Upload disable-tools.sh..."
scp $Script "${VPS}:/root/disable-tools.sh"
scp $Script "${VPS}:/root/oriphiel-ai/disable-tools.sh"

Write-Host "Pokrecem na VPS..."
ssh $VPS "mkdir -p /root/oriphiel-ai; sed -i 's/\r$//' /root/disable-tools.sh; bash /root/disable-tools.sh"

Write-Host ""
Write-Host "Zatvori tabove ai.oriph.io -> Novi razgovor -> test 2+2"
