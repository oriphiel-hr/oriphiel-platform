#!/usr/bin/env bash
# Oriphiel messaging - Postgres container + DB "oriphiel"
# (channels_accounts + contacts + messages)
set -euo pipefail

DB_NAME="${DB_NAME:-oriphiel}"
DB_USER="${DB_USER:-oriphiel}"
DB_PASS="${DB_PASS:-Oriphiel_DB_ChangeMe_2026}"
SCHEMA_FILE="${SCHEMA_FILE:-/tmp/oriphiel-messaging-schema.sql}"

echo "=== 1) Postgres kontejner ==="
if docker ps -a --format '{{.Names}}' | grep -qx 'oriphiel-postgres'; then
  echo "Kontejner oriphiel-postgres vec postoji - startam ako treba"
  docker start oriphiel-postgres >/dev/null || true
else
  docker run -d --name oriphiel-postgres \
    --restart unless-stopped \
    -e POSTGRES_DB="$DB_NAME" \
    -e POSTGRES_USER="$DB_USER" \
    -e POSTGRES_PASSWORD="$DB_PASS" \
    -p 127.0.0.1:5432:5432 \
    -v oriphiel_pgdata:/var/lib/postgresql/data \
    postgres:16
fi

echo "=== 2) Cekam da Postgres prihvaca veze ==="
for i in $(seq 1 40); do
  if docker exec oriphiel-postgres pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
    echo "Postgres ready ($i)"
    break
  fi
  sleep 1
done
docker exec oriphiel-postgres pg_isready -U "$DB_USER" -d "$DB_NAME"

echo "=== 3) Shema oriphiel_messaging (channels_accounts + contacts + messages) ==="
if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "Nedostaje schema: $SCHEMA_FILE" >&2
  exit 1
fi
# strip CRLF if schema came from Windows
sed -i 's/\r$//' "$SCHEMA_FILE"
docker exec -i oriphiel-postgres psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 < "$SCHEMA_FILE"

echo "=== 4) Provjera ==="
docker exec oriphiel-postgres psql -U "$DB_USER" -d "$DB_NAME" -c '\dt'
docker exec oriphiel-postgres psql -U "$DB_USER" -d "$DB_NAME" -c \
  'SELECT id, name, account_key, channel, address FROM channels_accounts ORDER BY id;'

echo
echo "GOTOVO - oriphiel_messaging baza: $DB_NAME"
echo "User:     $DB_USER"
echo "Password: $DB_PASS"
echo "Port:     5432 (samo 127.0.0.1 na VPS-u)"
echo
echo "n8n credential (s istog VPS-a):"
echo "  Host: 172.17.0.1"
echo "  Port: 5432"
echo "  Database: $DB_NAME"
echo "  User / Password: gore"
echo "  SSL: disable"
echo
echo "Sudreg: zasebna baza - scripts/sudreg/setup-sudreg-db.ps1"