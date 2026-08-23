#!/usr/bin/env bash
# Dodaje host folder + remount n8n kontejnera za attachmente.
# Workflowi ostaju (volume n8n_data se ne brise).
set -euo pipefail

ATTACH_HOST="${ATTACH_HOST:-/var/lib/oriphiel/attachments}"
ATTACH_CONT="${ATTACH_CONT:-/data/attachments}"
N8N_NAME="${N8N_NAME:-n8n}"

if ! docker ps -a --format '{{.Names}}' | grep -qx "$N8N_NAME"; then
  # mozda je ostao samo *_old_* nakon failed runa
  OLD=$(docker ps -a --format '{{.Names}}' | grep -E "^${N8N_NAME}_old_" | head -n1 || true)
  if [ -n "$OLD" ]; then
    echo "Nema $N8N_NAME, vracam $OLD -> $N8N_NAME"
    docker rename "$OLD" "$N8N_NAME"
    docker start "$N8N_NAME" || true
  else
    echo "Kontejner $N8N_NAME ne postoji" >&2
    exit 1
  fi
fi

echo "=== 1) Folder na hostu: $ATTACH_HOST ==="
mkdir -p "$ATTACH_HOST"
chown -R 1000:1000 "$ATTACH_HOST" || true
chmod 775 "$ATTACH_HOST"

if docker inspect "$N8N_NAME" --format '{{json .Mounts}}' 2>/dev/null | grep -q "$ATTACH_CONT"; then
  echo "Mount $ATTACH_CONT vec postoji — gotovo."
  docker inspect "$N8N_NAME" --format '{{json .Mounts}}'
  docker start "$N8N_NAME" >/dev/null 2>&1 || true
  exit 0
fi

IMAGE=$(docker inspect "$N8N_NAME" --format '{{.Config.Image}}')
echo "=== 2) Image: $IMAGE ==="

ENV_ARGS=()
while IFS= read -r line; do
  case "$line" in
    PATH=*|HOSTNAME=*|HOME=*|TERM=*) continue ;;
    "") continue ;;
    *) ENV_ARGS+=(-e "$line") ;;
  esac
done < <(docker inspect "$N8N_NAME" --format '{{range .Config.Env}}{{println .}}{{end}}')

# Unique port mappings (HostPort:ContainerPort)
declare -A SEEN_PORTS=()
PORT_ARGS=()
while IFS= read -r mapping; do
  [ -n "$mapping" ] || continue
  # normalize 5678:5678
  if [ -n "${SEEN_PORTS[$mapping]+x}" ]; then
    continue
  fi
  SEEN_PORTS[$mapping]=1
  PORT_ARGS+=(-p "$mapping")
done < <(docker inspect "$N8N_NAME" --format '{{range $p, $conf := .NetworkSettings.Ports}}{{range $conf}}{{if .HostPort}}{{printf "%s:%s\n" .HostPort $p}}{{end}}{{end}}{{end}}' | sed 's#/tcp##' | sort -u)

# Fallback ako Ports prazan (zaustavljen kontejner) - citaj HostConfig
if [ ${#PORT_ARGS[@]} -eq 0 ]; then
  while IFS= read -r mapping; do
    [ -n "$mapping" ] || continue
    PORT_ARGS+=(-p "$mapping")
  done < <(docker inspect "$N8N_NAME" --format '{{range $p, $arr := .HostConfig.PortBindings}}{{range $arr}}{{printf "%s:%s\n" .HostPort $p}}{{end}}{{end}}' | sed 's#/tcp##' | sort -u)
fi

DATA_VOL=$(docker inspect "$N8N_NAME" --format '{{range .Mounts}}{{if eq .Destination "/home/node/.n8n"}}{{.Name}}{{end}}{{end}}')
if [ -z "$DATA_VOL" ]; then
  DATA_VOL="n8n_data"
fi

RESTART=$(docker inspect "$N8N_NAME" --format '{{.HostConfig.RestartPolicy.Name}}')
[ -n "$RESTART" ] && [ "$RESTART" != "no" ] || RESTART="unless-stopped"

OLD_NAME="${N8N_NAME}_old_$(date +%Y%m%d%H%M%S)"

echo "=== 3) Stop + rename $N8N_NAME -> $OLD_NAME ==="
docker stop "$N8N_NAME" >/dev/null
docker rename "$N8N_NAME" "$OLD_NAME"

# Pričekaj da se port oslobodi
for i in $(seq 1 20); do
  if ! ss -lnt 2>/dev/null | grep -q ':5678' && ! netstat -lnt 2>/dev/null | grep -q ':5678'; then
    break
  fi
  # ako jos drzi port neki drugi n8n kontejner - stop
  EXTRA=$(docker ps --format '{{.ID}} {{.Names}} {{.Ports}}' | grep 5678 | awk '{print $1}' || true)
  if [ -n "$EXTRA" ]; then
    echo "Gasim proces/kontejner koji drzi 5678: $EXTRA"
    docker stop $EXTRA >/dev/null 2>&1 || true
  fi
  sleep 1
done

echo "=== 4) Novi kontejner s attachments mountom ==="
echo "  data volume: $DATA_VOL -> /home/node/.n8n"
echo "  attachments: $ATTACH_HOST -> $ATTACH_CONT"
echo "  ports: ${PORT_ARGS[*]:-none}"

if ! docker run -d --name "$N8N_NAME" \
  --restart "$RESTART" \
  "${PORT_ARGS[@]}" \
  "${ENV_ARGS[@]}" \
  -v "${DATA_VOL}:/home/node/.n8n" \
  -v "${ATTACH_HOST}:${ATTACH_CONT}" \
  "$IMAGE"; then
  echo "FAIL - vracam stari kontejner" >&2
  docker rm -f "$N8N_NAME" >/dev/null 2>&1 || true
  docker rename "$OLD_NAME" "$N8N_NAME"
  docker start "$N8N_NAME"
  exit 1
fi

sleep 2
docker ps --filter "name=^${N8N_NAME}$"
echo
echo "Mounts:"
docker inspect "$N8N_NAME" --format '{{json .Mounts}}'
echo
echo "GOTOVO. U n8n Write Binary File: $ATTACH_CONT/{message_id}/filename"
echo "Stari kontejner: $OLD_NAME — obrisi kad potvrdis:"
echo "  docker rm $OLD_NAME"