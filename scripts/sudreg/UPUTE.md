# Sudreg — upute

Sync Hrvatskog sudskog registra (Sudreg API) u Postgres bazu `sudreg` na **Ollama/Oriphiel VPS** (`186.240.157.80`), kontejner `oriphiel-postgres`.  
**Ne** na Ravnopar VPS.

Podaci (JSON cache, lock, logovi): `C:\GIT_PROJEKTI\oriphiel-platform\data\sudreg`  
Na VPS-u: `/opt/oriphiel-ai/data/sudreg`

---

## Brzi pregled naredbi

| Što | Naredba |
|-----|---------|
| Status / napredak | `Sudreg-Control.ps1 -Status` |
| Puna provjera (napredak+baza+data) | `Check-Sudreg.ps1` / `-Local` |
| Detaljna baza | `Check-Sudreg.ps1 -DbDetail -Local` |
| Zaustavi (nakon batcha) | `Sudreg-Control.ps1 -Stop` |
| Ubije proces | `Sudreg-Control.ps1 -Stop -ForceKill` |
| Obriši cijelu bazu | `Sudreg-Control.ps1 -Wipe -Force` |
| Dnevni / prvi unos | `Update-Sudreg.ps1 -FetchPromjeneFirst -SkipExistingPromjene` |
| Deploy na VPS | `Deploy-SudregToVps.ps1 -RunInstall` |

Na Linux VPS-u uvijek dodaj **`-Local`** (ili `export SUDREG_LOCAL=1`).

---

## Provjera do kud je došao unos

```powershell
# Brzi status
pwsh -File .\Sudreg-Control.ps1 -Status -Local

# Puna provjera: STANJE, phase, done/total, baza, progress.json, logovi
pwsh -File .\Check-Sudreg.ps1 -Local

# Detaljno (status firmi, scrape ok/err, zadnje firme)
pwsh -File .\Check-Sudreg.ps1 -DbDetail -Local

# Svi korisni SELECT-ovi
pwsh -File .\Check-Sudreg.ps1 -RunUsefulSql -Local

# Ručno progress
# cat /opt/oriphiel-ai/data/sudreg/run/progress.json
```

### Korisni SQL (baza `sudreg`)

Datoteka: `sql/useful-selects.sql`

```bash
docker exec -i oriphiel-postgres psql -U oriphiel -d sudreg \
  -f - < /opt/oriphiel-ai/scripts/sudreg/sql/useful-selects.sql
```

Primjeri:

```sql
SELECT key, value FROM sync_state;
SELECT count(*) FROM companies;
SELECT mbs, naziv, oib FROM companies WHERE naziv ILIKE '%...%' LIMIT 20;
SELECT scrape_ok, count(*) FROM companies GROUP BY scrape_ok;
```

---

## Model rada

### Prvi put (baza prazna)
1. Skine `/promjene` za dostupne snapshotove  
2. Scrape **svih** MBS-ova iz **najstarijeg** snapshota  
3. Scrape **razlike** (added MBS) do najnovijeg  
4. Spremi `last_imported_snapshot_id`

### Svaki dan (baza ima podatke)
1. Skine nove `/promjene` (ako treba)  
2. Usporedi `last_imported` ↔ najnoviji  
3. Scrape samo **deltu** (added MBS)  
4. Ažurira `last_imported`

Dok traje unos, **drugi pokušaj se odbija** (lock u `data/sudreg/run/lock.json`).

---

## Kontrola (status / stop / wipe)

```powershell
cd C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg

# Dokle je došlo, je li završilo, brojevi u bazi
powershell -NoProfile -ExecutionPolicy Bypass -File .\Sudreg-Control.ps1 -Status

# Isti izlaz kao JSON
powershell -NoProfile -ExecutionPolicy Bypass -File .\Sudreg-Control.ps1 -Status -AsJson

# Zahtjev za prekid (završi trenutni batch, pa stane)
powershell -NoProfile -ExecutionPolicy Bypass -File .\Sudreg-Control.ps1 -Stop

# Odmah ubij PID
powershell -NoProfile -ExecutionPolicy Bypass -File .\Sudreg-Control.ps1 -Stop -ForceKill

# Potpuno obriši bazu sudreg + ponovo kreiraj praznu shemu
powershell -NoProfile -ExecutionPolicy Bypass -File .\Sudreg-Control.ps1 -Wipe -Force

# + obriši i lokalne JSON datoteke (ostaju run/ i logs/)
powershell -NoProfile -ExecutionPolicy Bypass -File .\Sudreg-Control.ps1 -Wipe -Force -AlsoClearJsonCache

# Ukloni mrtvi lock (PID više ne živi)
powershell -NoProfile -ExecutionPolicy Bypass -File .\Sudreg-Control.ps1 -ClearStaleLock
```

### Što Status pokazuje
- radi li unos (`running`) ili je **završeno** / prekinuto / greška  
- fazu (`fetch_promjene`, `bootstrap_baseline`, `sync_scrape`, …)  
- `done/total`, `%`, `ok` / `err`, `snapshot_id`  
- broj firmi / osoba u bazi, `last_imported_snapshot_id`

Progress datoteka: `data/sudreg/run/progress.json`

---

## Unos podataka

### Preporučeno (prvi put i dnevno)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Update-Sudreg.ps1 `
  -FetchPromjeneFirst -SkipExistingPromjene
```

S Windowsa to ide preko SSH u Postgres na VPS.  
Na VPS-u (lokalni docker):

```bash
export SUDREG_LOCAL=1
pwsh -NoProfile -File /opt/oriphiel-ai/scripts/sudreg/Update-Sudreg.ps1 \
  -FetchPromjeneFirst -SkipExistingPromjene -Local
```

Ili dnevni omotač (log u `data/sudreg/logs/`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Run-SudregDaily.ps1
```

### Samo shema / baza (jednom)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-sudreg-db.ps1
# na VPS-u:
pwsh -File /opt/oriphiel-ai/scripts/sudreg/setup-sudreg-db.ps1 -Local
```

### Pomoćne skripte (rijetko ručno)

| Skripta | Uloga |
|---------|--------|
| `Get-SudregToken.ps1` | OAuth token (cache) |
| `Get-SudregSnapshots.ps1` | Lista snapshotova |
| `Get-SudregPromjene.ps1` | `/promjene` za jedan snapshot |
| `Get-SudregSubject.ps1` | Scrape jedne firme (MBS) |
| `Sync-SudregPromjeneAll.ps1` | Sve `/promjene` → JSON |
| `Compare-SudregPromjene.ps1` | Diff MBS (added/removed) |
| `Sync-SudregToPostgres.ps1` | Scrape + UPSERT (koristi Update) |

**Ne koristi `-MaxMbs` za pravi sync** — redoslijed MBS nije po važnosti; rezanje propušta prave promjene.

---

## Deploy na VPS

Cilj: `/opt/oriphiel-ai` na `root@186.240.157.80`  
Zahtijeva SSH ključ s tvog PC-a.

```powershell
# Upload + install (pwsh, shema, cron 06:15)
powershell -NoProfile -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Deploy-SudregToVps.ps1 -RunInstall

# Pokreni bootstrap u pozadini na VPS-u
powershell -NoProfile -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Deploy-SudregToVps.ps1 -SkipUpload -RunBootstrap
```

Ručno na VPS-u nakon upload-a:

```bash
bash /opt/oriphiel-ai/scripts/sudreg/vps-install-sudreg.sh
pwsh -File /opt/oriphiel-ai/scripts/sudreg/Sudreg-Control.ps1 -Status -Local
```

Cron (nakon installa): svaki dan **06:15** → `run-sudreg-daily.sh`

---

## Datoteke u ovom folderu

| Datoteka | Opis |
|----------|------|
| `Update-Sudreg.ps1` | Glavni tok (bootstrap + dnevna delta) |
| `Run-SudregDaily.ps1` | Dnevni omotač + log |
| `Sudreg-Control.ps1` | Status / Stop / Wipe |
| `Check-Sudreg.ps1` | Provjera napretka + baza + data dir |
| `SudregRun.ps1` | Lock, progress, abort |
| `SudregPg.ps1` | Postgres (SSH ili `-Local` docker) |
| `Sync-SudregToPostgres.ps1` | Scrape subjekata → UPSERT |
| `setup-sudreg-db.ps1` | CREATE DATABASE + shema |
| `sql/sudreg-schema.sql` | Tablice |
| `Deploy-SudregToVps.ps1` | Upload s Windowsa |
| `vps-install-sudreg.sh` | Install na Linuxu (pwsh, cron) |

---

## Tipični scenariji

**Pokrenuo sam unos — gdje sam?**  
`Sudreg-Control.ps1 -Status` → gledaj `phase`, `done/total`, `STANJE`.

**Želim nasilno stati.**  
`-Stop` pa ako ne stane za ~2 min: `-Stop -ForceKill`.

**Želim ispočetka.**  
1. `-Stop -ForceKill` (ako radi)  
2. `-Wipe -Force` (opcionalno `-AlsoClearJsonCache`)  
3. `Update-Sudreg.ps1 -FetchPromjeneFirst -SkipExistingPromjene`

**Drugi unos kaže da već traje, a proces je mrtav.**  
`Sudreg-Control.ps1 -ClearStaleLock`

---

## Napomene

- Baza `sudreg` je **odvojena** od `oriphiel` (mail/FB).  
- OAuth: env `SUDREG_CLIENT_ID` / `SUDREG_CLIENT_SECRET`, inače defaulti u `Get-SudregToken.ps1`.  
- S Windowsa bez SSH ključa `-Status` neće dohvatiti brojeve iz baze; na VPS-u koristi `-Local`.
