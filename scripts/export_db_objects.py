#!/usr/bin/env python3
"""
Export the current PostgreSQL schema objects to individual SQL files and
refresh lightweight Markdown documentation.

Prerequisites:
  - Python 3.10+
  - PostgreSQL client tools (pg_dump and psql) on PATH
  - Access to the target database/schema

Run from any directory:
  python export_db_objects.py

The script does not execute DDL against the database. It only reads metadata
and writes exports/docs to the folders configured below.
"""
from __future__ import annotations

import getpass
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

# ---- Project defaults; override with environment variables if needed ----
PROJECT_ROOT = Path(__file__).resolve().parent
DB_NAME = os.getenv("PGDATABASE", "SolarDB")
DB_USER = os.getenv("PGUSER", "solar_app_user")
DB_HOST = os.getenv("PGHOST", "localhost")
DB_PORT = os.getenv("PGPORT", "5432")
DB_SCHEMA = os.getenv("PGSCHEMA", "solar_app")

OBJECTS_ROOT = PROJECT_ROOT / "DB-Objects"
TABLE_SQL_DIR = OBJECTS_ROOT / "Tables"
FUNCTION_SQL_DIR = OBJECTS_ROOT / "Functions"
# Authored sources. This export must not write or delete DB-Objects/SQLFunctions
# or DB-Docs/SQLFunctions.
DOCS_ROOT = PROJECT_ROOT / "DB-Docs"
TABLE_DOC_DIR = DOCS_ROOT / "Tables"
FUNCTION_DOC_DIR = DOCS_ROOT / "Functions"
INDEX_DOC = DOCS_ROOT / "DATABASE_OBJECTS_INDEX.md"

def safe_filename(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9_.-]+", "_", value)
    return value.strip("._") or "object"

def run(command: list[str], *, env: dict[str, str], capture: bool = True) -> str:
    try:
        result = subprocess.run(
            command, env=env, text=True, encoding="utf-8",
            errors="replace", stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE, check=False
        )
    except FileNotFoundError as exc:
        raise RuntimeError(
            f"Command not found: {command[0]}. Install PostgreSQL client tools "
            "and ensure pg_dump/psql are on PATH."
        ) from exc
    if result.returncode != 0:
        raise RuntimeError(
            f"Command failed ({result.returncode}): {' '.join(command)}\n"
            f"{result.stderr.strip()}"
        )
    return result.stdout or ""

def psql_query(sql: str, env: dict[str, str]) -> list[str]:
    output = run([
        "psql", "-X", "-w", "-h", DB_HOST, "-p", DB_PORT, "-U", DB_USER,
        "-d", DB_NAME, "-v", "ON_ERROR_STOP=1", "-A", "-t", "-q", "-c", sql
    ], env=env)
    return [line for line in output.splitlines() if line.strip()]

def main() -> int:
    for binary in ("psql", "pg_dump"):
        if shutil.which(binary) is None:
            print(f"ERROR: '{binary}' not found on PATH. Install PostgreSQL client tools.")
            return 2

    password = os.getenv("PGPASSWORD")
    if not password:
        password = getpass.getpass(f"Password for PostgreSQL user {DB_USER}: ")

    env = os.environ.copy()
    env["PGPASSWORD"] = password
    env.setdefault("PGCLIENTENCODING", "UTF8")

    # Verify connection and schema exists.
    version = run([
        "psql", "-X", "-w", "-h", DB_HOST, "-p", DB_PORT, "-U", DB_USER,
        "-d", DB_NAME, "-v", "ON_ERROR_STOP=1", "-A", "-t", "-c",
        "SELECT current_database() || ' | ' || current_user"
    ], env=env).strip()
    schema_check = psql_query(
        "SELECT 1 FROM information_schema.schemata "
        f"WHERE schema_name = '{DB_SCHEMA.replace(chr(39), chr(39)*2)}'",
        env
    )
    if not schema_check:
        print(f"ERROR: schema '{DB_SCHEMA}' was not found in database '{DB_NAME}'.")
        return 3

    # Encode metadata rows as base64 JSON so comments/newlines cannot break parsing.
    table_query = f"""
      SELECT encode(convert_to(json_build_array(
               c.relname,
               COALESCE(obj_description(c.oid, 'pg_class'), '')
             )::text, 'UTF8'), 'base64')
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = '{DB_SCHEMA.replace(chr(39), chr(39)*2)}'
        AND c.relkind IN ('r','p')
      ORDER BY c.relname
    """
    table_rows = psql_query(table_query, env)

    function_query = f"""
      SELECT encode(convert_to(json_build_array(
               p.oid::text, p.proname,
               pg_get_function_identity_arguments(p.oid),
               pg_get_function_result(p.oid), l.lanname,
               COALESCE(obj_description(p.oid, 'pg_proc'), ''),
               pg_get_functiondef(p.oid)
             )::text, 'UTF8'), 'base64')
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      JOIN pg_language l ON l.oid = p.prolang
      WHERE n.nspname = '{DB_SCHEMA.replace(chr(39), chr(39)*2)}'
        AND p.prokind IN ('f','p')
      ORDER BY p.proname, pg_get_function_identity_arguments(p.oid)
    """
    function_rows = psql_query(function_query, env)

    for directory in (TABLE_SQL_DIR, FUNCTION_SQL_DIR, TABLE_DOC_DIR, FUNCTION_DOC_DIR):
        directory.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
    table_names: list[str] = []
    function_names: list[str] = []
    errors: list[str] = []

    # Export each table using pg_dump, preserving PostgreSQL's real DDL output.
    import base64
    import json

    for encoded_row in table_rows:
        try:
            table_name, table_comment = json.loads(base64.b64decode(encoded_row).decode("utf-8"))
        except Exception as exc:
            errors.append(f"Could not parse table metadata row: {exc}")
            continue
        table_names.append(table_name)
        filename = safe_filename(f"{DB_SCHEMA}.{table_name}") + ".sql"
        out_file = TABLE_SQL_DIR / filename
        command = [
            "pg_dump", "-w", "-h", DB_HOST, "-p", DB_PORT, "-U", DB_USER,
            "-d", DB_NAME, "--schema-only", "--no-owner", "--no-privileges",
            "--table", f"{DB_SCHEMA}.{table_name}"
        ]
        try:
            ddl = run(command, env=env)
            if not ddl.strip():
                errors.append(f"No DDL returned for table {DB_SCHEMA}.{table_name}")
                continue
            out_file.write_text(
                f"-- Generated from live database: {DB_NAME}.{DB_SCHEMA}.{table_name}\n"
                f"-- Exported at: {timestamp}\n"
                f"-- Generated by export_db_objects.py; do not edit this export manually.\n\n"
                + ddl, encoding="utf-8"
            )
        except RuntimeError as exc:
            errors.append(str(exc))
            continue

        doc_file = TABLE_DOC_DIR / (safe_filename(f"{DB_SCHEMA}.{table_name}") + ".md")
        doc_file.write_text(
            f"# Table: `{DB_SCHEMA}.{table_name}`\n\n"
            f"- Database: `{DB_NAME}`\n- Schema: `{DB_SCHEMA}`\n"
            f"- Last exported: {timestamp}\n"
            f"- Table comment: {table_comment or '(no table comment in database)'}\n\n"
            "## Columns\n\n"
            "| Column | Data type | Nullable | Default | Comment |\n"
            "|---|---|---|---|---|\n"
            + get_columns_markdown(table_name, env)
            + "\n## Notes\n\n"
            "This document is generated from the live database catalog. "
            "Review business purpose and usage notes here if needed, but do not "
            "manually edit generated SQL files.\n",
            encoding="utf-8"
        )

    import base64
    import json

    for encoded_row in function_rows:
        try:
            oid, name, identity_args, result_type, language, comment, definition = json.loads(
                base64.b64decode(encoded_row).decode("utf-8")
            )
        except Exception as exc:
            errors.append(f"Could not parse function metadata row: {exc}")
            continue
        signature = f"{name}({identity_args})"
        function_names.append(signature)
        fname = safe_filename(f"{DB_SCHEMA}.{name}_{identity_args or 'no_args'}")
        sql_file = FUNCTION_SQL_DIR / f"{fname}.sql"
        sql_file.write_text(
            f"-- Generated from live database: {DB_NAME}.{DB_SCHEMA}.{signature}\n"
            f"-- Exported at: {timestamp}\n"
            f"-- Generated by export_db_objects.py; do not edit this export manually.\n\n"
            + definition.strip() + "\n",
            encoding="utf-8"
        )
        doc_file = FUNCTION_DOC_DIR / f"{fname}.md"
        doc_file.write_text(
            f"# Function/Procedure: `{DB_SCHEMA}.{signature}`\n\n"
            f"- Database: `{DB_NAME}`\n- Schema: `{DB_SCHEMA}`\n"
            f"- Return type: `{result_type}`\n- Language: `{language}`\n"
            f"- Last exported: {timestamp}\n"
            f"- Database comment: {comment or '(no function comment in database)'}\n\n"
            "## Definition\n\n"
            "The matching `.sql` file contains the current definition retrieved "
            "from `pg_get_functiondef`.\n\n"
            "## Business purpose / usage\n\n"
            "Add or maintain the purpose, input payload contract, return JSON structure, "
            "validation rules, and callers here. This section is not inferred from "
            "the database definition.\n",
            encoding="utf-8"
        )

    index_lines = [
        "# Database Objects Index", "",
        f"- Database: `{DB_NAME}`",
        f"- Schema: `{DB_SCHEMA}`",
        f"- Connection check: `{version}`",
        f"- Exported at: {timestamp}", "",
        "## Tables", "",
        f"Tables found: **{len(table_names)}**", ""
    ]
    index_lines += [f"- [`{name}`](Tables/{safe_filename(f'{DB_SCHEMA}.{name}')}.md)" for name in table_names]
    index_lines += ["", "## Functions and procedures", "",
                    f"Functions/procedures found: **{len(function_names)}**", ""]
    index_lines += [
        f"- `{signature}`" for signature in function_names
    ]
    if errors:
        index_lines += ["", "## Export warnings/errors", ""]
        index_lines += [f"- {err.replace(chr(10), ' ')}" for err in errors]
    INDEX_DOC.write_text("\n".join(index_lines) + "\n", encoding="utf-8")

    print(f"\nConnected: {version}")
    print(f"Schema: {DB_SCHEMA}")
    print(f"Tables found: {len(table_names)}")
    print(f"Functions/procedures found: {len(function_names)}")
    print(f"Table SQL folder: {TABLE_SQL_DIR}")
    print(f"Function SQL folder: {FUNCTION_SQL_DIR}")
    print(f"Documentation folder: {DOCS_ROOT}")
    print(f"Index: {INDEX_DOC}")
    if errors:
        print(f"\nCompleted with {len(errors)} warning(s):")
        for err in errors:
            print(" - " + err.replace("\n", " "))
        return 1
    print("\nExport completed.")
    return 0

def get_columns_markdown(table_name: str, env: dict[str, str]) -> str:
    # Encode each value as hex to safely preserve arbitrary comments/defaults.
    sql = f"""
      SELECT encode(convert_to(concat_ws(E'\\t',
        a.attname,
        format_type(a.atttypid, a.atttypmod),
        CASE WHEN a.attnotnull THEN 'NO' ELSE 'YES' END,
        COALESCE(pg_get_expr(d.adbin, d.adrelid), ''),
        COALESCE(col_description(c.oid, a.attnum), '')
      ), 'UTF8'), 'hex')
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid
      LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
      WHERE n.nspname = '{DB_SCHEMA.replace(chr(39), chr(39)*2)}'
        AND c.relname = '{table_name.replace(chr(39), chr(39)*2)}'
        AND a.attnum > 0 AND NOT a.attisdropped
      ORDER BY a.attnum
    """
    rows = psql_query(sql, env)
    output = []
    for row in rows:
        try:
            decoded = bytes.fromhex(row).decode("utf-8").split("\t")
            decoded += [""] * (5 - len(decoded))
            col, dtype, nullable, default, comment = decoded[:5]
            def esc(value: str) -> str:
                return value.replace("|", "\\|").replace("\n", " ").replace("\r", " ").replace("`", "\\`")
            output.append(
                f"| `{esc(col)}` | `{esc(dtype)}` | {nullable} | "
                f"`{esc(default) if default else ''}` | {esc(comment) or '—'} |"
            )
        except Exception:
            output.append(f"| `{row}` | (parse error) | — | — | — |")
    return "\n".join(output) if output else "| — | — | — | — | — |"

if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
