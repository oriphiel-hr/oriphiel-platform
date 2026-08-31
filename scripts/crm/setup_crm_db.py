"""Kreira bazu oriphiel_crm + shemu (preko DATABASE_URL / CRM hosta).

Primjer (SSH tunnel na 5433):
  set DATABASE_URL=postgresql://oriphiel:PASS@127.0.0.1:5433/sudreg
  python setup_crm_db.py
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from urllib.parse import urlparse, urlunparse

import psycopg

DB_NAME = os.environ.get("CRM_DB_NAME", "oriphiel_crm")
SCHEMA = Path(__file__).resolve().parent / "sql" / "oriphiel-crm-schema.sql"


def admin_url_from_env() -> str:
    raw = (
        os.environ.get("CRM_SETUP_URL")
        or os.environ.get("DATABASE_URL")
        or os.environ.get("CRM_DATABASE_URL")
        or ""
    ).strip()
    if not raw:
        print("Postavi DATABASE_URL ili CRM_SETUP_URL (npr. ...@127.0.0.1:5433/sudreg)", file=sys.stderr)
        sys.exit(1)
    p = urlparse(raw)
    # connect to postgres maintenance DB for CREATE DATABASE
    return urlunparse((p.scheme, p.netloc, "/postgres", "", "", ""))


def crm_url_from_admin(admin: str) -> str:
    p = urlparse(admin)
    return urlunparse((p.scheme, p.netloc, f"/{DB_NAME}", "", "", ""))


def main() -> None:
    if not SCHEMA.is_file():
        raise SystemExit(f"Nedostaje shema: {SCHEMA}")

    admin = admin_url_from_env()
    print(f"1) CREATE DATABASE {DB_NAME} (ako ne postoji)...")
    with psycopg.connect(admin, connect_timeout=10, autocommit=True) as conn:
        exists = conn.execute(
            "SELECT 1 FROM pg_database WHERE datname = %s", (DB_NAME,)
        ).fetchone()
        if exists:
            print(f"   već postoji: {DB_NAME}")
        else:
            conn.execute(f'CREATE DATABASE "{DB_NAME}"')
            print(f"   kreirano: {DB_NAME}")

    crm = crm_url_from_admin(admin)
    schema_dir = SCHEMA.parent
    files = [SCHEMA.name, "web-finder-jobs.sql"]
    print(f"2) Primjena sheme na {DB_NAME}...")
    with psycopg.connect(crm, connect_timeout=10, autocommit=True) as conn:
        for name in files:
            path = schema_dir / name
            if not path.is_file():
                print(f"   skip (nema): {name}")
                continue
            conn.execute(path.read_text(encoding="utf-8"))
            print(f"   OK {name}")
        tables = conn.execute(
            """
            SELECT tablename FROM pg_tables
            WHERE schemaname = 'public'
            ORDER BY 1
            """
        ).fetchall()
        print("3) Tablice:", ", ".join(t[0] for t in tables))

    print()
    print(f"GOTOVO. CRM_DATABASE_URL={crm}")


if __name__ == "__main__":
    main()
