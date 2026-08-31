# Sudreg UI — interni preglednik

Read-only web interface za Postgres bazu `sudreg`: pretraga, filter statusa, paginacija, detalj tvrtke.

## Zašto se stranica „ne učitavala“

1. Stari **Basic Auth** je vraćao **401** bez HTML-a → browser izgleda prazno.  
   Sada: **login forma** na `/login` (`admin` / `changeme`).
2. Ako nema SSH tunela / krivi `DATABASE_URL`, upit na bazu visi.  
   Sada: timeout 5 s + poruka greške na stranici.

## Lokalno (Windows)

```powershell
# Terminal 1 — tunnel do Postgresa na VPS-u
ssh -L 5432:127.0.0.1:5432 root@186.240.157.80

# Terminal 2
cd C:\GIT_PROJEKTI\oriphiel-platform\apps\sudreg-ui
.\.venv\Scripts\Activate.ps1
copy .env.example .env   # prvi put — uredi DATABASE_URL (Postgres lozinka)
uvicorn app.main:app --host 127.0.0.1 --port 8091
```

Otvori: http://127.0.0.1:8091 → login → `admin` / `changeme`

Postgres lozinka: `docker exec oriphiel-postgres printenv POSTGRES_PASSWORD` (na VPS-u)

## Deploy na VPS

```powershell
powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\apps\sudreg-ui\Deploy-SudregUiToVps.ps1 -CreateEnvIfMissing -ApplyTrgm
```

Zatim:

```powershell
ssh -L 8091:127.0.0.1:8091 root@186.240.157.80
```

Browser: http://127.0.0.1:8091  
Lozinka UI: `ssh ... "grep SUDREG_UI_PASSWORD /opt/oriphiel-ai/apps/sudreg-ui/.env"`

## pg_trgm

Uključeno u deploy s `-ApplyTrgm`, ili ručno SQL: `sql/pg_trgm_indexes.sql`

## Masovna pretraga weba (VPS worker)

1. U UI: **Masovno** → *Pokreni u pozadini* (piše posao u `oriphiel_crm`).
2. Na VPS-u container **`web-finder-worker`** čita posao i traži webove (laptop može biti ugašen).
3. Sprema u CRM samo visoki skor (≥60, OIB/MBS na stranici). Pauza/nastavak iz UI.

```powershell
# Deploy UI + worker
powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\apps\sudreg-ui\Deploy-SudregUiToVps.ps1

# Logovi workera
ssh root@186.240.157.80 "docker logs -f web-finder-worker"
```

Env: `CRM_DATABASE_URL=postgresql://oriphiel:…@oriphiel-postgres:5432/oriphiel_crm`

## Env

| Varijabla | Opis |
|---|---|
| `DATABASE_URL` | `postgresql://oriphiel:...@host:5432/sudreg` |
| `CRM_DATABASE_URL` | baza `oriphiel_crm` (web, jobovi) |
| `SUDREG_UI_USER` / `SUDREG_UI_PASSWORD` | login |
| `SESSION_SECRET` | cookie potpis |
| `HOST` / `PORT` | default `127.0.0.1:8091` |
