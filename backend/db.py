"""
db.py
-----
MySQL connection manager and reusable query helpers.
Uses mysql-connector-python with connection pooling.
"""

import mysql.connector
from mysql.connector import Error, pooling

# ─────────────────────────────────────────────
# CONNECTION CONFIGURATION
# ─────────────────────────────────────────────
DB_CONFIG = {
    "host":     "localhost",
    "port":     3306,
    "user":     "root",
    "password": "12345678",
    "database": "psl_analytics",
    "charset":  "utf8mb4",
    "use_pure": True,
    "auth_plugin": "mysql_native_password",
}

_pool = None


def get_pool():
    global _pool
    if _pool is None:
        _pool = pooling.MySQLConnectionPool(
            pool_name="psl_pool",
            pool_size=5,
            pool_reset_session=True,
            **DB_CONFIG
        )
    return _pool


def get_connection():
    return get_pool().get_connection()


# ─────────────────────────────────────────────
# QUERY HELPERS
# ─────────────────────────────────────────────

def execute_query(sql, params=None):
    """
    Execute a SELECT query and return a list of dicts.
    params: tuple or list of values for %s placeholders.
    Always uses parameterized queries — never string concat.
    """
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute(sql, params or ())
        results = cursor.fetchall()
        return results
    except Error as e:
        raise RuntimeError(f"DB query error: {e}") from e
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


def execute_write(sql, params=None):
    """
    Execute an INSERT/UPDATE/DELETE and return affected row count.
    Auto-commits on success.
    """
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(sql, params or ())
        conn.commit()
        return cursor.rowcount
    except Error as e:
        if conn:
            conn.rollback()
        raise RuntimeError(f"DB write error: {e}") from e
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


def call_procedure(name, args=None):
    """
    Call a stored procedure by name with positional args.
    Returns a list of result sets (each result set is a list of dicts).
    MySQL stored procedures can return multiple result sets.
    """
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.callproc(name, args or [])
        result_sets = []
        for result in cursor.stored_results():
            result_sets.append(result.fetchall())
        return result_sets
    except Error as e:
        raise RuntimeError(f"Procedure '{name}' error: {e}") from e
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


def call_function(name, args=None):
    """
    Call a user-defined scalar function using SELECT func(%s, %s, ...).
    Returns the single scalar value.
    """
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor()
        placeholders = ", ".join(["%s"] * len(args)) if args else ""
        sql = f"SELECT {name}({placeholders}) AS result"
        cursor.execute(sql, args or ())
        row = cursor.fetchone()
        return row[0] if row else None
    except Error as e:
        raise RuntimeError(f"Function '{name}' error: {e}") from e
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


def get_isolation_level():
    """Fetch the current session transaction isolation level."""
    rows = execute_query("SELECT @@transaction_isolation AS isolation_level")
    if rows:
        return rows[0]["isolation_level"]
    return "UNKNOWN"
