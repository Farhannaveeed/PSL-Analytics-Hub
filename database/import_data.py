"""
import_data.py
-------------
Imports all 5 PSL CSV files into MySQL.
Tables imported in FK-safe order: teams → players → matches → innings → deliveries
Uses INSERT IGNORE for full idempotency (safe to run multiple times).
Uses executemany() for batch inserts.

Run: python database/import_data.py
Requires: mysql-connector-python  (pip install mysql-connector-python)
"""

import csv
import os
import sys
import time
import mysql.connector
from mysql.connector import Error

# ─────────────────────────────────────────────
# CONFIGURATION — update credentials as needed
# ─────────────────────────────────────────────
DB_CONFIG = {
    "host":     "localhost",
    "port":     3306,
    "user":     "root",
    "password": "12345678",
    "database": "psl_analytics",
    "charset":  "utf8mb4",
    "autocommit": False,
    "auth_plugin": "mysql_native_password",
}

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")

# ─────────────────────────────────────────────
# TABLE DEFINITIONS: column mapping + SQL
# ─────────────────────────────────────────────

TABLES = [
    {
        "name": "teams",
        "file": "teams.csv",
        "columns": ["team_id", "team_name", "city", "home_ground", "founded_year"],
        "sql": """
            INSERT IGNORE INTO teams
                (team_id, team_name, city, home_ground, founded_year)
            VALUES
                (%s, %s, %s, %s, %s)
        """,
    },
    {
        "name": "players",
        "file": "players.csv",
        "columns": ["player_id", "player_name", "nationality", "role",
                    "batting_style", "bowling_style", "team_id"],
        "sql": """
            INSERT IGNORE INTO players
                (player_id, player_name, nationality, role,
                 batting_style, bowling_style, team_id)
            VALUES
                (%s, %s, %s, %s, %s, %s, %s)
        """,
    },
    {
        "name": "matches",
        "file": "matches.csv",
        "columns": ["match_id", "season", "match_date", "venue", "city",
                    "team1_id", "team2_id", "toss_winner_id", "toss_decision",
                    "winner_id", "win_by_runs", "win_by_wickets",
                    "player_of_match_id", "match_type"],
        "sql": """
            INSERT IGNORE INTO matches
                (match_id, season, match_date, venue, city,
                 team1_id, team2_id, toss_winner_id, toss_decision,
                 winner_id, win_by_runs, win_by_wickets,
                 player_of_match_id, match_type)
            VALUES
                (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
    },
    {
        "name": "innings",
        "file": "innings.csv",
        "columns": ["innings_id", "match_id", "innings_number",
                    "batting_team_id", "bowling_team_id",
                    "total_runs", "total_wickets", "total_overs", "extras"],
        "sql": """
            INSERT IGNORE INTO innings
                (innings_id, match_id, innings_number,
                 batting_team_id, bowling_team_id,
                 total_runs, total_wickets, total_overs, extras)
            VALUES
                (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
    },
    {
        "name": "deliveries",
        "file": "deliveries.csv",
        "columns": ["delivery_id", "innings_id", "match_id",
                    "over_number", "ball_number",
                    "batsman_id", "bowler_id",
                    "runs_scored", "extras", "extra_type",
                    "is_wicket", "dismissal_type", "fielder_id"],
        "sql": """
            INSERT IGNORE INTO deliveries
                (delivery_id, innings_id, match_id,
                 over_number, ball_number,
                 batsman_id, bowler_id,
                 runs_scored, extras, extra_type,
                 is_wicket, dismissal_type, fielder_id)
            VALUES
                (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
    },
]

BATCH_SIZE = 500   # rows per executemany() call


# ─────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────

def none_if_empty(val):
    """Convert empty-string CSV values to None (SQL NULL)."""
    if val == "" or val is None:
        return None
    return val


def read_csv(filepath, columns):
    """Read a CSV file, return list of tuples in column order."""
    rows = []
    with open(filepath, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(tuple(none_if_empty(row.get(col)) for col in columns))
    return rows


def import_table(conn, table_def):
    """Import one table from its CSV. Returns (rows_attempted, rows_inserted, rows_skipped)."""
    name     = table_def["name"]
    filepath = os.path.join(DATA_DIR, table_def["file"])
    columns  = table_def["columns"]
    sql      = table_def["sql"]

    if not os.path.exists(filepath):
        print(f"  [{name}] ERROR: File not found: {filepath}")
        return 0, 0, 0

    print(f"  [{name}] Reading {filepath}...", end=" ", flush=True)
    rows = read_csv(filepath, columns)
    total = len(rows)
    print(f"{total} rows found.")

    cursor = conn.cursor()
    inserted = 0
    skipped  = 0
    start    = time.time()

    try:
        # Process in batches for memory efficiency
        for i in range(0, total, BATCH_SIZE):
            batch = rows[i : i + BATCH_SIZE]
            cursor.executemany(sql, batch)
            inserted += cursor.rowcount
            print(f"  [{name}] Batch {i // BATCH_SIZE + 1}: "
                  f"{min(i + BATCH_SIZE, total)}/{total} rows processed...", end="\r", flush=True)

        conn.commit()
        elapsed = time.time() - start
        skipped = total - inserted
        print(f"  [{name}] Done in {elapsed:.1f}s — "
              f"Inserted: {inserted}, Skipped (duplicates): {skipped}")

    except Error as e:
        conn.rollback()
        print(f"\n  [{name}] ERROR: {e}")
        inserted = 0
        skipped  = total
    finally:
        cursor.close()

    return total, inserted, skipped


# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────

def main():
    print("=" * 60)
    print("  PSL Analytics — Data Import Script")
    print("=" * 60)

    # Verify data directory exists
    if not os.path.isdir(DATA_DIR):
        print(f"ERROR: Data directory not found: {DATA_DIR}")
        print("Run  python data/generate_data.py  first.")
        sys.exit(1)

    # Connect to MySQL
    print(f"\nConnecting to MySQL at {DB_CONFIG['host']}:{DB_CONFIG['port']}...")
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        print("Connected successfully.\n")
    except Error as e:
        print(f"Connection failed: {e}")
        sys.exit(1)

    # Disable FK checks during import for speed; re-enable after
    cursor = conn.cursor()
    cursor.execute("SET FOREIGN_KEY_CHECKS = 0;")
    cursor.execute("SET SESSION bulk_insert_buffer_size = 256*1024*1024;")
    cursor.close()

    # Import each table
    summary = []
    for table_def in TABLES:
        print(f"\n{'─'*50}")
        print(f"  Importing: {table_def['name']}")
        print(f"{'─'*50}")
        try:
            attempted, inserted, skipped = import_table(conn, table_def)
            summary.append({
                "table":    table_def["name"],
                "attempted": attempted,
                "inserted":  inserted,
                "skipped":   skipped,
                "status":   "OK" if inserted > 0 or attempted == 0 else "PARTIAL",
            })
        except Exception as e:
            print(f"  Unexpected error importing {table_def['name']}: {e}")
            summary.append({
                "table":    table_def["name"],
                "attempted": 0,
                "inserted":  0,
                "skipped":   0,
                "status":   "FAILED",
            })

    # Re-enable FK checks
    cursor = conn.cursor()
    cursor.execute("SET FOREIGN_KEY_CHECKS = 1;")
    cursor.close()
    conn.close()

    # Print summary table
    print("\n" + "=" * 60)
    print("  IMPORT SUMMARY")
    print("=" * 60)
    print(f"  {'Table':<20} {'Attempted':>10} {'Inserted':>10} {'Skipped':>10} {'Status':>8}")
    print(f"  {'─'*20} {'─'*10} {'─'*10} {'─'*10} {'─'*8}")
    total_attempted = total_inserted = total_skipped = 0
    for s in summary:
        print(f"  {s['table']:<20} {s['attempted']:>10} {s['inserted']:>10} {s['skipped']:>10} {s['status']:>8}")
        total_attempted += s["attempted"]
        total_inserted  += s["inserted"]
        total_skipped   += s["skipped"]
    print(f"  {'─'*20} {'─'*10} {'─'*10} {'─'*10} {'─'*8}")
    print(f"  {'TOTAL':<20} {total_attempted:>10} {total_inserted:>10} {total_skipped:>10}")
    print("=" * 60)
    print("Import complete. You can safely re-run this script — INSERT IGNORE prevents duplicates.")


if __name__ == "__main__":
    main()
