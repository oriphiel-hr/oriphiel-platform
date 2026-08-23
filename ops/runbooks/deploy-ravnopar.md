# Runbook — Deploy Ravnopar

App: https://ravnopar.com  
VPS: `186.240.157.39` → `/var/www/Render/ravnopar`  
Kod (lokalno): `C:\GIT_PROJEKTI\oriphiel-platform\ravnopar`  
GitHub: https://github.com/oriphiel-hr/oriphiel-platform/tree/master/ravnopar

---

## 1. Push koda

```powershell
cd C:\GIT_PROJEKTI\oriphiel-platform
git status
git add ravnopar
git commit -m "ravnopar: opis promjene"
git push origin master
```

> Na VPS-u putanja još može syncati iz starog `Render` repoa. Ako VPS još vuče `oriphiel-hr/Render`, uskladi remote ili kopiraj ručno dok ne prebaciš deploy na ovaj monorepo.

---

## 2. Frontend rebuild (na VPS-u)

```bash
ssh root@186.240.157.39
cd /var/www/Render/ravnopar
bash scripts/vps-rebuild-web.sh
# ili bez git reset:
SKIP_GIT=1 bash scripts/vps-rebuild-web.sh
```

Skripta: `npm ci` + `npm run build` u `frontend-next` + `pm2 restart ravnopar-web`.

---

## 3. API restart / fix

```bash
bash scripts/vps-fix-api.sh
# ili
cd /var/www/Render/ravnopar/backend
npm ci
npx prisma migrate deploy
npx prisma generate
pm2 restart ravnopar-api --update-env
```

---

## 4. Provjera

```bash
pm2 status
curl -sS https://ravnopar.com/ | head
# health / stats — vidi ravnopar/docs/MONITORING.md
```

Hard refresh u browseru: Ctrl+Shift+R.

---

## 5. Umami (analitika)

```bash
cd /var/www/Render/ravnopar
bash scripts/vps-setup-umami.sh          # prvi put
bash scripts/vps-fix-umami-analytics.sh # env + rebuild
```

Docs: [`../../ravnopar/docs/MONITORING.md`](../../ravnopar/docs/MONITORING.md)

---

## Env / tajne

- Primjeri: `ravnopar/backend/.env.example`, `ravnopar/.env.render.example`
- Stvarne vrijednosti → **Bitwarden**, ne u git

---

## Related

- [`../bash/vps-checks.sh.md`](../bash/vps-checks.sh.md)
- [`../sql/ravnopar-mysql.sql`](../sql/ravnopar-mysql.sql)
- [`../../ravnopar/docs/RENDER-ENV.md`](../../ravnopar/docs/RENDER-ENV.md)
- Render blueprint: `ravnopar/render.yaml`
