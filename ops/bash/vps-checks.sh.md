# Bash — VPS checks (ad-hoc)

Kopiraj naredbe na SSH sesiju. Hostovi: [`../../infra/hosts.yaml`](../../infra/hosts.yaml)

---

## Oriphiel AI VPS (`186.240.157.80`)

```bash
# SSH
ssh root@186.240.157.80

# Docker / Postgres
docker ps --format 'table {{.Names}}\t{{.Status}}'
docker exec -i oriphiel-postgres psql -U oriphiel -d oriphiel -c 'SELECT count(*) FROM messages;'
docker exec -i oriphiel-postgres psql -U oriphiel -d sudreg -c 'SELECT count(*) FROM companies;'

# Ollama
curl -s http://127.0.0.1:11434/api/tags | head
systemctl status ollama --no-pager | head -20

# Messaging check
cd /root/oriphiel-ai/oriphiel_messaging
bash check-messaging.sh

# Backfill / AI status
watch -n2 cat /tmp/oriphiel-imap-backfill-mario.vitt.json
watch -n5 cat /tmp/oriphiel-ai-enrich-mario.vitt.json
pgrep -af 'sync-imap-backfill|enrich-existing'
tail -n 50 /tmp/oriphiel-imap-backfill-last.log
tail -n 50 /tmp/oriphiel-ai-enrich-last.log

# Attachmenti
du -sh /var/lib/oriphiel/attachments/email/* 2>/dev/null | head
ls /var/lib/oriphiel/attachments/email/ | head

# Sudreg
pwsh -File /opt/oriphiel-ai/scripts/sudreg/Check-Sudreg.ps1 -Local -StatusOnly
ls -la /opt/oriphiel-ai/data/sudreg/ | head
```

---

## Ravnopar VPS (`186.240.157.39`)

```bash
ssh root@186.240.157.39

cd /var/www/Render/ravnopar
pm2 status
pm2 logs ravnopar-api --lines 40
pm2 logs ravnopar-web --lines 40

# Health (ako postoji endpoint)
curl -sS https://ravnopar.com/api/health || curl -sS http://127.0.0.1:3001/health || true

# Umami
cd /var/www/Render/ravnopar/deploy/umami
docker compose ps
```

---

## Disk / opće

```bash
df -h
free -h
uptime
```
