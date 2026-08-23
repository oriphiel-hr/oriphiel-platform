# Oriphiel AI — upload branding + apply na VPS
# Pokreni u Windows PowerShellu (pita za root lozinku)
$ErrorActionPreference = "Stop"
$VPS = "root@186.240.157.80"
$Root = Split-Path -Parent $PSScriptRoot
$Assets = Join-Path $Root "assets"
$Scripts = Join-Path $Root "scripts"

Write-Host "Paket: $Root"
Write-Host "1) Upload branding + skripti..."
ssh $VPS "mkdir -p /root/branding-upload /opt/open-webui/branding /root/oriphiel-ai"
scp `
  "$Assets\logo.png" `
  "$Assets\favicon.png" `
  "$Assets\logo-white.png" `
  "$Assets\logo-icon.png" `
  "$Assets\logo-pattern.png" `
  "$Assets\custom.css" `
  "$Assets\oriphiel-brand.js" `
  "$Scripts\apply-branding.sh" `
  "${VPS}:/root/branding-upload/"

scp `
  "$Scripts\disable-tools.sh" `
  "$Scripts\apply-branding.sh" `
  "${VPS}:/root/oriphiel-ai/"

# Kompatibilnost sa starom putanjom
ssh $VPS "cp -f /root/oriphiel-ai/disable-tools.sh /root/disable-tools.sh"

Write-Host "2) Primjena branding na VPS (restart Open WebUI)..."
ssh $VPS "sed -i 's/\r$//' /root/branding-upload/apply-branding.sh /root/oriphiel-ai/*.sh /root/disable-tools.sh; bash /root/branding-upload/apply-branding.sh"

Write-Host ""
Write-Host "Gotovo. https://ai.oriph.io -> novi tab (Ctrl+Shift+R)"
Write-Host "Tools su OFF (builtin_tools=false). Koristi Novi razgovor."
