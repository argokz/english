#!/usr/bin/env python3
"""
Check database structure - verify all tables and columns exist.
"""
import os
import sys
from urllib.parse import urlparse

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(os.path.dirname(__file__)), ".env"))

try:
    import psycopg2
except ImportError:
    print("Install psycopg2: pip install psycopg2-binary")
    sys.exit(1)


def get_connection_params():
    url = os.getenv("DATABASE_URL", "postgresql://postgres:Danil228@localhost:5440/english_app")
    url = url.replace("postgresql+asyncpg://", "postgresql://", 1)
    p = urlparse(url)
    return {
        "host": p.hostname,
        "port": p.port or 5432,
        "user": p.username or "postgres",
        "password": p.password or "",
        "dbname": (p.path or "/english_app").strip("/").split("?")[0] or "english_app",
    }


def main():
    params = get_connection_params()
    conn = psycopg2.connect(**params)
    cur = conn.cursor()
    
    print("Checking database structure...\n")
    
    # Check pgvector extension
    cur.execute("SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'vector')")
    has_vector = cur.fetchone()[0]
    print(f"pgvector extension: {'OK' if has_vector else 'MISSING'}")
    
    # Check tables
    required_tables = ['users', 'decks', 'cards', 'review_log']
    print("\nTables:")
    for table in required_tables:
        cur.execute(f"""
            SELECT EXISTS(
                SELECT 1 FROM information_schema.tables 
                WHERE table_name = '{table}'
            )
        """)
        exists = cur.fetchone()[0]
        status = "OK" if exists else "MISSING"
        print(f"  - {table}: {status}")
        
        if exists:
            # Check columns
            cur.execute(f"""
                SELECT column_name, data_type 
                FROM information_schema.columns 
                WHERE table_name = '{table}'
                ORDER BY ordinal_position
            """)
            columns = cur.fetchall()
            for col_name, col_type in columns:
                print(f"    - {col_name}: {col_type}")
    
    # Check embedding column specifically
    print("\nEmbedding column:")
    cur.execute("""
        SELECT column_name, data_type 
        FROM information_schema.columns 
        WHERE table_name = 'cards' AND column_name = 'embedding'
    """)
    embedding = cur.fetchone()
    if embedding:
        print(f"  - {embedding[0]}: {embedding[1]} (OK)")
    else:
        print("  - MISSING")
    
    cur.close()
    conn.close()
    print("\nDone!")


if __name__ == "__main__":
    main()

