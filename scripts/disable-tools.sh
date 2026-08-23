#!/bin/bash
# Oriphiel AI — Open WebUI: ugasi builtin tools + zadrži branding
# Pokreće se NA VPS-u (ne na Windowsu).
set -euo pipefail

BRAND=/opt/open-webui/branding
CACHE_V=45

echo "=== Oriphiel: gasim Builtin Tools (notes/tasks) ==="

if [[ ! -d "$BRAND" ]]; then
  echo "UPOZORENJE: nema $BRAND — prvo pokreni apply-branding.sh"
fi

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
  -v "$BRAND/logo.png:/app/backend/open_webui/static/logo.png:ro" \
  -v "$BRAND/favicon.png:/app/backend/open_webui/static/favicon.png:ro" \
  -v "$BRAND/splash.png:/app/backend/open_webui/static/splash.png:ro" \
  -v "$BRAND/logo-white.png:/app/backend/open_webui/static/logo-white.png:ro" \
  -v "$BRAND/logo-icon.png:/app/backend/open_webui/static/logo-icon.png:ro" \
  -v "$BRAND/logo-pattern.png:/app/backend/open_webui/static/logo-pattern.png:ro" \
  -v "$BRAND/custom.css:/app/backend/open_webui/static/custom.css:ro" \
  -v "$BRAND/oriphiel-brand.js:/app/backend/open_webui/static/oriphiel-brand.js:ro" \
  -v "$BRAND/logo.png:/app/build/static/logo.png:ro" \
  -v "$BRAND/favicon.png:/app/build/static/favicon.png:ro" \
  -v "$BRAND/splash.png:/app/build/static/splash.png:ro" \
  -v "$BRAND/logo-white.png:/app/build/static/logo-white.png:ro" \
  -v "$BRAND/logo-icon.png:/app/build/static/logo-icon.png:ro" \
  -v "$BRAND/logo-pattern.png:/app/build/static/logo-pattern.png:ro" \
  -v "$BRAND/custom.css:/app/build/static/custom.css:ro" \
  -v "$BRAND/oriphiel-brand.js:/app/build/static/oriphiel-brand.js:ro" \
  ghcr.io/open-webui/open-webui:main

echo "Cekam WebUI..."
for i in $(seq 1 40); do
  if curl -fsS http://127.0.0.1:8080/ >/dev/null 2>&1; then
    echo "WebUI UP"
    break
  fi
  sleep 2
done

# Samo pravi Open WebUI config — ne diraj embedding modele
docker exec open-webui sh -c 'python3 - <<'"'"'PY'"'"'
import json, os

def force_off(o, changed):
    if isinstance(o, dict):
        for k in list(o.keys()):
            kl = str(k).lower()
            if kl in ("builtin_tools",):
                if o[k] is not False:
                    o[k] = False
                    changed[0] = True
            if kl in ("function_calling",):
                if o[k] not in ("none", False, None, ""):
                    o[k] = "none"
                    changed[0] = True
            if kl == "capabilities" and isinstance(o[k], dict):
                if o[k].get("builtin_tools") is not False:
                    o[k]["builtin_tools"] = False
                    changed[0] = True
            force_off(o[k], changed)
    elif isinstance(o, list):
        for v in o:
            force_off(v, changed)

for p in (
    "/app/backend/data/config.json",
    "/app/backend/data/cache/config.json",
):
    if not os.path.isfile(p):
        print("missing", p)
        continue
    try:
        with open(p, "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception as e:
        print("skip", p, e)
        continue
    changed = [False]
    force_off(cfg, changed)
    if changed[0]:
        with open(p, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False)
        print("updated", p)
    else:
        print("no change", p)
PY'

docker exec open-webui sh -c "
INDEX=/app/build/index.html
if [ -f \"\$INDEX\" ]; then
  sed -i '/custom.css/d;/oriphiel-brand.js/d;/oriphiel-inline-boot/d' \"\$INDEX\"
  sed -i 's#</head>#<link rel=\"stylesheet\" href=\"/static/custom.css?v=${CACHE_V}\" /></head>#' \"\$INDEX\"
  sed -i 's#</body>#<script src=\"/static/oriphiel-brand.js?v=${CACHE_V}\"></script></body>#' \"\$INDEX\"
fi
" || true

docker restart open-webui >/dev/null
sleep 6
docker ps --filter name=open-webui --format 'table {{.Names}}\t{{.Status}}'
echo ""
echo "GOTOVO."
echo "Zatvori SVE tabove ai.oriph.io -> novi tab -> Novi razgovor"
echo "Test: Koliko je 2+2? Odgovori samo brojem."
