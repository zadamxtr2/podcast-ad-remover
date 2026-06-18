import subprocess
import sys
from pathlib import Path

from app.core.config import settings
from app.infra.database import get_db_connection, init_db
from app.infra.repository import ApiTokenRepository


def test_link_api_token_user_script_lists_and_links_token(isolated_data_dir):
    init_db()
    with get_db_connection() as conn:
        cursor = conn.execute(
            "INSERT INTO users (username, password_hash, is_admin) VALUES (?, ?, 0)",
            ("assistant", "hash"),
        )
        user_id = cursor.lastrowid
        conn.commit()

    repo = ApiTokenRepository()
    token = repo.create("Existing token", scopes=["read"])
    token_id = repo.list_active()[0]["id"]
    script = Path("scripts/link_api_token_user.py")

    listed = subprocess.run(
        [sys.executable, str(script), "--db-path", settings.DB_PATH, "--list"],
        check=True,
        capture_output=True,
        text=True,
    )
    linked = subprocess.run(
        [
            sys.executable,
            str(script),
            "--db-path",
            settings.DB_PATH,
            "--token-id",
            str(token_id),
            "--username",
            "assistant",
        ],
        check=True,
        capture_output=True,
        text=True,
    )

    token_row = repo.validate(token)

    assert "Existing token" in listed.stdout
    assert "unlinked" in listed.stdout
    assert f"Linked API token id={token_id}" in linked.stdout
    assert token_row["user_id"] == user_id
    assert token_row["username"] == "assistant"
