# Ravnopar — monitoring

## Health check

Backend endpoint (za UptimeRobot, Better Stack, itd.):

```
GET https://ravnopar-backend.onrender.com/health
```

Očekivani odgovor (200):

```json
{
  "ok": true,
  "service": "ravnopar-backend",
  "startedAt": "2026-06-28T...",
  "database": "ok"
}
```

Ako baza nije dostupna → **503** i `"database": "error"`.

---

## UptimeRobot (besplatno)

1. Registracija na [uptimerobot.com](https://uptimerobot.com)
2. **Add New Monitor**
   - Monitor Type: **HTTP(s)**
   - Friendly Name: `Ravnopar Backend`
   - URL: `https://ravnopar-backend.onrender.com/health`
   - Monitoring Interval: 5 min
3. **Alert Contacts** → tvoj email (i opcionalno SMS)
4. Spremi

Opcionalno drugi monitor za frontend (`ravnopar` static site):

```
https://ravnopar.onrender.com/
```

---

## Render Logs

Render Dashboard → **ravnopar-backend** → **Logs**

Korisno za:
- SMTP / email greške (`[ravnopar-mail:error]`)
- Prisma migracije pri deployu
- 5xx greške

---

## Ručna provjera

```bash
curl https://ravnopar-backend.onrender.com/health
curl https://ravnopar-backend.onrender.com/api/matchmaking/public-stats
```

---

## Cron (anti-ghosting)

Postavi `CRON_SECRET` na backendu i pozivaj dnevno:

```bash
curl -X POST https://ravnopar-backend.onrender.com/api/matchmaking/internal/cron/sweep \
  -H "x-cron-secret: YOUR_SECRET"
```

Zatvara neaktivne razgovore, šalje upozorenja i istječe stare PENDING zahtjeve.

Opcionalno: `MONTHLY_OPERATING_COST_CENTS=2500` za postotak pokrivenosti donacijama.

---

## Umami (posjete stranici)

Self-host na VPS-u (`analytics.ravnopar.com`). Analitika se učitava **odmah** (bez praćenih kolačića — ne čeka cookie banner).

**Setup (jednom):**

```bash
# DNS: A analytics → VPS IP
cd /var/www/Render/ravnopar
bash scripts/vps-setup-umami.sh
```

Zatim u Umami UI: promijeni default lozinku (`admin` / `umami`) → dodaj website `ravnopar.com` → kopiraj Website ID + API token.

| Servis | Env | Vrijednost |
|--------|-----|------------|
| **ravnopar-web** | `NEXT_PUBLIC_ANALYTICS_URL` | `https://analytics.ravnopar.com/script.js` |
| **ravnopar-web** | `NEXT_PUBLIC_UMAMI_WEBSITE_ID` | UUID websitea |
| **ravnopar-api** | `UMAMI_BASE_URL` | `https://analytics.ravnopar.com` |
| **ravnopar-api** | `UMAMI_WEBSITE_ID` | isti UUID |
| **ravnopar-api** | `UMAMI_USERNAME` / `UMAMI_PASSWORD` | **preporučeno** (token se osvježava sam) |
| **ravnopar-api** | `UMAMI_API_TOKEN` | opcionalno; JWT na self-hostu **ističe** |
| **ravnopar-api** | `UMAMI_SHARE_URL` | opcionalno, share link za iframe |
| **ravnopar-api** | `UMAMI_SITE_LABEL` | `ravnopar.com` |

Ako Admin pokaže **Invalid token**: u `backend/.env` stavi Umami login umjesto starog tokena, pa restart API-ja:

```bash
cd /var/www/Render/ravnopar/backend
# u .env:
# UMAMI_USERNAME=admin
# UMAMI_PASSWORD=tvoja-umami-lozinka
# (UMAMI_API_TOKEN možeš obrisati ili ostaviti — login ima prednost)
pm2 restart ravnopar-api --update-env
```

Ili jednokratno osvježi token skriptom: `bash scripts/vps-fix-umami-analytics.sh`

Nakon env: `npm run build` u `frontend-next` + `pm2 restart ravnopar-web ravnopar-api --update-env`.

**Admin** (`/admin`) prikazuje brojke iz Umami API-ja.

**Napomena:** Search Console pokazuje samo Google klikove; Umami pokriva sve posjete.

---

## Admin račun (produkcija)

Admin konzola: `https://ravnopar.oriph.io/admin` — samo uloga **ADMIN**.

Lokalno se ne može spojiti na Render bazu. Kreiraj admina u **Render Shellu**:

1. [dashboard.render.com](https://dashboard.render.com) → **ravnopar-backend** → **Shell**
2. Pokreni (zamijeni lozinku):

```bash
node scripts/create-admin.js ravnopar@oriph.io TvojaJakaLozinka123
```

3. Prijava na `/auth` s tim emailom → `/admin`

Provjera uloge:

```bash
node scripts/check-user.js ravnopar@oriph.io
```

Lokalno (s `.env` koji ima `DATABASE_URL`):

```bash
cd ravnopar/backend
npm run admin:create -- ravnopar@oriph.io TvojaLozinka
```

---

| Key | Opis |
|-----|------|
| `MESSAGE_EMAIL_COOLDOWN_MS` | Cooldown email obavijesti za poruke (default 900000 = 15 min) |
| `ADMIN_NOTIFY_EMAIL` | Alert email za admin prijave |
