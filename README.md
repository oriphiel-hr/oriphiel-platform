# oriphiel-platform

Monorepo za Oriphiel infrastrukturu i produkte.

**Lokalna lokacija:** `C:\GIT_PROJEKTI\oriphiel-platform`

## Servisi

| Servis | Lokalno | Deploy |
|--------|---------|--------|
| **Ravnopar** (dating app) | `ravnopar/` | Render + VPS `186.240.157.39` |
| Open WebUI (ai.oriph.io) | `assets/`, `scripts/deploy-*.ps1` | VPS srv1890026 |
| Messaging (n8n + IMAP) | `scripts/oriphiel_messaging/` | `/root/oriphiel-ai/oriphiel_messaging/` |
| Sudreg sync | `scripts/sudreg/` | `/opt/oriphiel-ai/scripts/sudreg/` |

Detalji o hostovima: `infra/hosts.yaml`

## Struktura

```
oriphiel-platform/
├── ravnopar/                 # backend, frontend-next, mobile, deploy
├── assets/                   # Open WebUI branding
├── scripts/
│   ├── oriphiel_messaging/
│   └── sudreg/
├── docs/
├── data/
└── infra/
    └── hosts.yaml
```

## Brzi start (Windows)

```powershell
# Ravnopar backend (lokalno)
cd C:\GIT_PROJEKTI\oriphiel-platform\ravnopar\backend
copy .env.example .env
npm install && npm run dev

# Open WebUI branding
powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\deploy-all.ps1

# Messaging deploy
powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging\Deploy-ImapBackfill.ps1

# Sudreg deploy
powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Deploy-SudregToVps.ps1
```

## Git

Svi Oriphiel projekti u jednom repou:

```
C:\GIT_PROJEKTI\oriphiel-platform\    ← ovaj repo (ravnopar + infra + skripte)
C:\GIT_PROJEKTI\Render\               ← ostali Render projekti (Uslugar, …)
```

**Napomena:** `ravnopar` je premješten iz `C:\GIT_PROJEKTI\Render\ravnopar` u ovaj monorepo.  
Na VPS-u putanja ostaje `/var/www/Render/ravnopar` dok je ne promijeniš ručno.

## Dokumentacija

- `ravnopar/README.md` — Ravnopar quick start
- `ravnopar/docs/` — produkcija, monitoring, Render env
- `UPUTE.txt` — Open WebUI kratke upute
- `scripts/oriphiel_messaging/README.md` — mail pipeline
- `scripts/sudreg/UPUTE.md` — Sudreg
