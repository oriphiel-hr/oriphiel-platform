#!/bin/bash
# Oriphiel AI — apply branding + Open WebUI (tools OFF)
# Izvor datoteka: /root/branding-upload (upload s Windowsa)
set -euo pipefail

SRC=/root/branding-upload
DST=/opt/open-webui/branding
CACHE_V=45
mkdir -p "$DST"

cp -f "$SRC/logo.png" "$DST/logo.png"
cp -f "$SRC/favicon.png" "$DST/favicon.png"
cp -f "$SRC/logo-white.png" "$DST/logo-white.png"
cp -f "$SRC/logo-icon.png" "$DST/logo-icon.png"
cp -f "$SRC/logo-pattern.png" "$DST/logo-pattern.png"
cp -f "$SRC/logo.png" "$DST/splash.png"
cp -f "$SRC/custom.css" "$DST/custom.css"
cp -f "$SRC/oriphiel-brand.js" "$DST/oriphiel-brand.js"
chmod 644 "$DST"/*

docker rm -f open-webui >/dev/null 2>&1 || true

docker run -d --name open-webui --restart always \
  --network=host \
  -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
  -e WEBUI_NAME="Oriphiel AI" \
  -e WEBUI_URL="https://ai.oriph.io" \
  -e ENABLE_PERSISTENT_CONFIG=False \
  -e 'DEFAULT_MODEL_METADATA={"capabilities":{"builtin_tools":false,"vision":true,"file_upload":true,"web_search":false,"image_generation":false}}' \
  -e 'DEFAULT_MODEL_PARAMS={"function_calling":"none"}' \
  -v open-webui:/app/backend/data \
  -v "$DST/logo.png:/app/backend/open_webui/static/logo.png:ro" \
  -v "$DST/favicon.png:/app/backend/open_webui/static/favicon.png:ro" \
  -v "$DST/splash.png:/app/backend/open_webui/static/splash.png:ro" \
  -v "$DST/logo-white.png:/app/backend/open_webui/static/logo-white.png:ro" \
  -v "$DST/logo-icon.png:/app/backend/open_webui/static/logo-icon.png:ro" \
  -v "$DST/logo-pattern.png:/app/backend/open_webui/static/logo-pattern.png:ro" \
  -v "$DST/custom.css:/app/backend/open_webui/static/custom.css:ro" \
  -v "$DST/oriphiel-brand.js:/app/backend/open_webui/static/oriphiel-brand.js:ro" \
  -v "$DST/logo.png:/app/build/static/logo.png:ro" \
  -v "$DST/favicon.png:/app/build/static/favicon.png:ro" \
  -v "$DST/splash.png:/app/build/static/splash.png:ro" \
  -v "$DST/logo-white.png:/app/build/static/logo-white.png:ro" \
  -v "$DST/logo-icon.png:/app/build/static/logo-icon.png:ro" \
  -v "$DST/logo-pattern.png:/app/build/static/logo-pattern.png:ro" \
  -v "$DST/custom.css:/app/build/static/custom.css:ro" \
  -v "$DST/oriphiel-brand.js:/app/build/static/oriphiel-brand.js:ro" \
  ghcr.io/open-webui/open-webui:main

for i in $(seq 1 25); do
  if curl -fsS http://127.0.0.1:8080/ >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

docker exec open-webui sh -c "
INDEX=/app/build/index.html
if [ -f \"\$INDEX\" ]; then
  sed -i '/custom.css/d' \"\$INDEX\"
  sed -i '/oriphiel-brand.js/d' \"\$INDEX\"
  sed -i '/oriphiel-inline-boot/d' \"\$INDEX\"
  sed -i \"s#</head>#<link rel=\\\"stylesheet\\\" href=\\\"/static/custom.css?v=${CACHE_V}\\\" /><script id=\\\"oriphiel-inline-boot\\\">(function(){function L(){var s=document.createElement(\\\"script\\\");s.src=\\\"/static/oriphiel-brand.js?v=${CACHE_V}\\\";s.defer=true;document.head.appendChild(s);} if(document.body)L(); else document.addEventListener(\\\"DOMContentLoaded\\\",L); setTimeout(L,500);})();</script></head>#\" \"\$INDEX\"
  sed -i \"s#</body>#<script src=\\\"/static/oriphiel-brand.js?v=${CACHE_V}\\\"></script></body>#\" \"\$INDEX\"
  grep -n 'custom.css\\|oriphiel' \"\$INDEX\" || true
fi
"

echo "=== Provjera ==="
curl -sI "http://127.0.0.1:8080/static/custom.css?v=${CACHE_V}" | grep -iE 'HTTP|content-length' || true
curl -sI "http://127.0.0.1:8080/static/oriphiel-brand.js?v=${CACHE_V}" | grep -iE 'HTTP|content-length' || true
docker ps --filter name=open-webui --format 'table {{.Names}}\t{{.Status}}'
echo "GOTOVO. Novi tab + Ctrl+Shift+R."
echo "v${CACHE_V}: branding + builtin_tools=false + function_calling=none"
