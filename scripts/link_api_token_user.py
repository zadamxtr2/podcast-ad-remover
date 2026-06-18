#!/usr/bin/env python3
"""List API tokens and link an existing API token to a dashboard user."""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from app.core.config import settings  # noqa: E402


def _connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def _list_tokens(conn: sqlite3.Connection) -> int:
    rows = conn.execute(
        """
        SELECT at.id,
               at.token_prefix,
               at.name,
               at.scopes,
               at.created_at,
               at.last_used_at,
               at.revoked_at,
               u.id AS user_id,
               u.username
        FROM api_tokens at
        LEFT JOIN users u ON u.id = at.user_id
        ORDER BY at.created_at DESC
        """
    ).fetchall()
    if not rows:
        print("No API tokens found.")
        return 0

    for row in rows:
        status = "revoked" if row["revoked_at"] else "active"
        user = f'{row["username"]} (id {row["user_id"]})' if row["username"] else "unlinked"
        print(
            f'id={row["id"]} prefix={row["token_prefix"]} status={status} '
            f'user={user} name="{row["name"]}" scopes={row["scopes"]} '
            f'last_used={row["last_used_at"] or "never"}'
        )
    return 0


def _find_token(conn: sqlite3.Connection, token_id: int | None, token_prefix: str | None) -> sqlite3.Row:
    if token_id is not None:
        row = conn.execute(
            "SELECT id, token_prefix, name FROM api_tokens WHERE id = ? AND revoked_at IS NULL",
            (token_id,),
        ).fetchone()
    else:
        row = conn.execute(
            "SELECT id, token_prefix, name FROM api_tokens WHERE token_prefix = ? AND revoked_at IS NULL",
            (token_prefix,),
        ).fetchone()

    if not row:
        raise ValueError("Active API token not found")
    return row


def _find_user(conn: sqlite3.Connection, user_id: int | None, username: str | None) -> sqlite3.Row:
    if user_id is not None:
        row = conn.execute("SELECT id, username FROM users WHERE id = ?", (user_id,)).fetchone()
    else:
        row = conn.execute("SELECT id, username FROM users WHERE username = ?", (username,)).fetchone()

    if not row:
        raise ValueError("User not found")
    return row


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Link an existing Podcast Ad Remover API token to a dashboard user."
    )
    parser.add_argument("--db-path", default=settings.DB_PATH, help="Path to podcasts.db. Defaults to configured DB path.")
    parser.add_argument("--list", action="store_true", help="List API tokens and exit.")

    token_group = parser.add_mutually_exclusive_group()
    token_group.add_argument("--token-id", type=int, help="Active API token id to link.")
    token_group.add_argument("--token-prefix", help="Active API token display prefix to link.")

    user_group = parser.add_mutually_exclusive_group()
    user_group.add_argument("--user-id", type=int, help="Dashboard user id to link to.")
    user_group.add_argument("--username", help="Dashboard username to link to.")

    args = parser.parse_args()

    with _connect(args.db_path) as conn:
        if args.list:
            return _list_tokens(conn)

        if args.token_id is None and not args.token_prefix:
            parser.error("one of --token-id or --token-prefix is required unless --list is used")
        if args.user_id is None and not args.username:
            parser.error("one of --user-id or --username is required unless --list is used")

        try:
            token = _find_token(conn, args.token_id, args.token_prefix)
            user = _find_user(conn, args.user_id, args.username)
        except ValueError as exc:
            print(f"Error: {exc}", file=sys.stderr)
            return 1

        conn.execute("UPDATE api_tokens SET user_id = ? WHERE id = ?", (user["id"], token["id"]))
        conn.commit()

    print(
        f'Linked API token id={token["id"]} prefix={token["token_prefix"]} '
        f'to user id={user["id"]} username="{user["username"]}".'
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
