import psycopg
from pathlib import Path

u = "postgresql://oriphiel:Oriphiel_DB_ChangeMe_2026@127.0.0.1:5433/oriphiel_crm"
root = Path(__file__).resolve().parent
for name in ("oriphiel-crm-schema.sql", "web-finder-jobs.sql", "company-websites-multi.sql"):
    p = root / name
    if not p.is_file():
        p = root.parent.parent / "scripts" / "crm" / "sql" / name
    sql = p.read_text(encoding="utf-8")
    with psycopg.connect(u, autocommit=True) as c:
        c.execute(sql)
        print("applied", p.name)
with psycopg.connect(u) as c:
    print(c.execute("select tablename from pg_tables where schemaname='public' order by 1").fetchall())
