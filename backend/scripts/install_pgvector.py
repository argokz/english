#!/usr/bin/env python3
"""
Install pgvector extension and add embedding column to cards table.
Run from backend dir: python scripts/install_pgvector.py
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
        "dbname": (p.path or "/english_app").strip("/").split("?")[0] or "english_app",
    }


def main():
    params = get_connection_params()
    dbname = params["dbname"]
    conn_params = {k: v for k, v in params.items() if k != "dbname"}
    
    print(f"Connecting to database {dbname!r}...")
    conn = psycopg2.connect(dbname=dbname, **conn_params)
    conn.autocommit = True
    cur = conn.cursor()
    
    # Try to create extension directly
    print("Installing pgvector extension...")
    try:
        cur.execute("CREATE EXTENSION IF NOT EXISTS vector")
        print("SUCCESS: pgvector extension installed successfully!")
    except Exception as e:
        error_msg = str(e)
        if "extension" in error_msg.lower() and "does not exist" in error_msg.lower():
            print("ERROR: pgvector extension is not available in PostgreSQL.")
            print("   You need to install pgvector in PostgreSQL first.")
            print("\n   For Windows PostgreSQL:")
            print("   1. Download pgvector from: https://github.com/pgvector/pgvector/releases")
            print("   2. Find the version matching your PostgreSQL (e.g., pgvector-v0.5.1-windows-x64.zip)")
            print("   3. Extract and copy:")
            print("      - vector.dll -> C:\\Program Files\\PostgreSQL\\16\\lib\\")
            print("      - vector.control and vector--*.sql -> C:\\Program Files\\PostgreSQL\\16\\share\\extension\\")
            print("   4. Restart PostgreSQL service")
            print("   5. Run this script again")
        else:
            print(f"ERROR: Failed to create extension: {e}")
            print("   Make sure you have superuser privileges.")
        cur.close()
        conn.close()
        sys.exit(1)
    
    # Check if embedding column exists
    print("Checking embedding column...")
    cur.execute("""
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name = 'cards' AND column_name = 'embedding'
    """)
    column_exists = cur.fetchone() is not None
    
    if column_exists:
        print("SUCCESS: Column 'embedding' already exists in 'cards' table.")
    else:
        print("Adding 'embedding' column to 'cards' table...")
        try:
            cur.execute("ALTER TABLE cards ADD COLUMN embedding vector(768)")
            print("SUCCESS: Column 'embedding' added successfully!")
        except Exception as e:
            print(f"ERROR: Failed to add column: {e}")
            cur.close()
            conn.close()
            sys.exit(1)
    
    cur.close()
    conn.close()
    print("\nDone! pgvector is ready to use.")


if __name__ == "__main__":
    main()

