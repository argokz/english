#!/usr/bin/env python3
"""
Create database and install pgvector extension.
Uses DATABASE_URL from env (or .env) to get host, port, user, password.
Creates the target database if it does not exist, then runs CREATE EXTENSION vector.
Run from backend dir: python scripts/init_db.py
"""
import os
import sys
from urllib.parse import urlparse

# Load .env from backend dir
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(os.path.dirname(__file__)), ".env"))

try:
    import psycopg2
    from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
except ImportError:
    print("Install psycopg2: pip install psycopg2-binary")
    sys.exit(1)


def get_connection_params():
    url = os.getenv("DATABASE_URL", "postgresql://postgres:Danil228@localhost:5440/english_app")
    url = url.replace("postgresql+asyncpg://", "postgresql://", 1)
    p = urlparse(url)
    if not p.hostname:
        raise ValueError("Invalid DATABASE_URL: missing host")
    return {
        "host": p.hostname,
        "port": p.port or 5432,
        "user": p.username or "postgres",
        "password": p.password or "",
        "dbname_target": (p.path or "/english_app").strip("/").split("?")[0] or "english_app",
    }


def main():
    params = get_connection_params()
    target_db = params["dbname_target"]
    conn_params = {k: v for k, v in params.items() if k != "dbname_target"}

    # Connect to default 'postgres' database to create target DB
    conn_params["dbname"] = "postgres"
    conn = psycopg2.connect(**conn_params)
    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cur = conn.cursor()

    cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (target_db,))
    if cur.fetchone() is None:
        cur.execute(f'CREATE DATABASE "{target_db}"')
        print(f"Database {target_db!r} created.")
    else:
        print(f"Database {target_db!r} already exists.")

    cur.close()
    conn.close()

    # Connect to target database and install pgvector
    conn_params["dbname"] = target_db
    conn = psycopg2.connect(**conn_params)
    conn.autocommit = True
    cur = conn.cursor()
    cur.execute("CREATE EXTENSION IF NOT EXISTS vector")
    print("Extension pgvector installed (or already present).")
    cur.close()
    conn.close()
    print("Done. Run: alembic upgrade head")


if __name__ == "__main__":
    main()
