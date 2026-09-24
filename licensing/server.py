"""Small, local-first activation service for BoltSnip.

Put an HTTPS reverse proxy in front of this service before exposing it publicly.
"""

import argparse
import contextlib
import getpass
import hashlib
import hmac
import http.server
import os
import re
import secrets
import sqlite3
import urllib.parse
from pathlib import Path


DEVICE_RE = re.compile(r"^[0-9a-f]{64}$")
CUSTOM_CODE_RE = re.compile(r"^[A-Za-z]{1,128}$")


def key_hash(key):
    return hashlib.sha256(key.strip().encode("ascii")).hexdigest()


def connect(path):
    path = Path(path)
    existed = path.exists()
    db = sqlite3.connect(path, timeout=10)
    if os.name == "posix" and not existed:
        os.chmod(path, 0o600)
    db.execute(
        "CREATE TABLE IF NOT EXISTS licenses "
        "(key_hash TEXT PRIMARY KEY, device TEXT, created_utc TEXT NOT NULL "
        "DEFAULT (datetime('now')))"
    )
    columns = {row[1] for row in db.execute("PRAGMA table_info(licenses)")}
    additions = {
        "code": "TEXT",
        "activated_utc": "TEXT",
        "last_check_utc": "TEXT",
        "transfer_count": "INTEGER NOT NULL DEFAULT 0",
    }
    for name, definition in additions.items():
        if name not in columns:
            db.execute("ALTER TABLE licenses ADD COLUMN {} {}".format(name, definition))
    db.commit()
    return db


def create_license(db):
    key = "BS-" + secrets.token_urlsafe(24)
    with db:
        db.execute(
            "INSERT INTO licenses (key_hash, code) VALUES (?, ?)",
            (key_hash(key), key),
        )
    return key


def create_custom_license(db, key):
    if not CUSTOM_CODE_RE.fullmatch(key):
        raise ValueError("code must contain only English letters (A-Z, a-z), up to 128 characters")
    with db:
        db.execute(
            "INSERT INTO licenses (key_hash, code) VALUES (?, ?)",
            (key_hash(key), key),
        )
    return key


def list_licenses(db):
    return db.execute(
        "SELECT key_hash, code, device, created_utc, activated_utc, "
        "last_check_utc, transfer_count FROM licenses ORDER BY created_utc, key_hash"
    ).fetchall()


def print_licenses(rows):
    print("Total: {}".format(len(rows)))
    for index, row in enumerate(rows, 1):
        digest, code, device, created, activated, checked, transfers = row
        display_code = code or "<older code unavailable; hash {}>".format(digest[:12])
        print("{}. {}".format(index, display_code))
        print("   Status: {}".format("bound" if device else "unused"))
        print("   Device: {}".format(device or "-"))
        print("   Created UTC: {}".format(created))
        print("   Activated UTC: {}".format(activated or "-"))
        print("   Last check UTC: {}".format(checked or "-"))
        print("   Transfers: {}".format(transfers))


def release_license(db, key):
    with db:
        cursor = db.execute(
            "UPDATE licenses SET device = NULL WHERE key_hash = ?",
            (key_hash(key),),
        )
    return cursor.rowcount == 1


def authorize(db, key, device, activate):
    if not key or len(key) > 128 or not key.isascii() or not DEVICE_RE.fullmatch(device):
        return "INVALID"
    digest = key_hash(key)
    db.execute("BEGIN IMMEDIATE")
    try:
        row = db.execute(
            "SELECT key_hash, device FROM licenses WHERE key_hash = ?", (digest,)
        ).fetchone()
        if row is None:
            result = "INVALID"
        elif activate:
            if row[1] is None or not hmac.compare_digest(row[1], device):
                db.execute(
                    "UPDATE licenses SET device = ?, activated_utc = datetime('now'), "
                    "last_check_utc = NULL, transfer_count = transfer_count + ? "
                    "WHERE key_hash = ?",
                    (device, 1 if row[1] is not None else 0, digest),
                )
            result = "OK"
        elif row[1] is not None and hmac.compare_digest(row[1], device):
            db.execute(
                "UPDATE licenses SET last_check_utc = datetime('now') WHERE key_hash = ?",
                (digest,),
            )
            result = "OK"
        else:
            result = "INACTIVE"
        db.commit()
        return result
    except Exception:
        db.rollback()
        raise


def make_handler(database):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path not in ("/activate", "/check"):
                self.send_error(404)
                return
            try:
                size = int(self.headers.get("Content-Length", "0"))
                if size < 1 or size > 1024:
                    self.send_error(400)
                    return
                fields = urllib.parse.parse_qs(
                    self.rfile.read(size).decode("ascii"), strict_parsing=True
                )
                key = fields["key"][0]
                device = fields["device"][0]
                if len(key) > 128:
                    self.send_error(400)
                    return
                with contextlib.closing(connect(database)) as db:
                    result = authorize(db, key, device, activate=self.path == "/activate")
            except (KeyError, IndexError, ValueError, UnicodeError):
                self.send_error(400)
                return
            data = result.encode("ascii")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=ascii")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, format_string, *args):
            # Never put license keys or device IDs in access logs.
            pass

    return Handler


def main(argv=None):
    parser = argparse.ArgumentParser(description="BoltSnip activation service")
    parser.add_argument("--db", type=Path, required=True)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("create")
    diy = commands.add_parser("diy")
    diy.add_argument("code", nargs="?")
    commands.add_parser("list")
    commands.add_parser("release")
    serve = commands.add_parser("serve")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8765)
    args = parser.parse_args(argv)
    args.db.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with contextlib.closing(connect(args.db)) as db:
        if args.command == "create":
            print(create_license(db))
        elif args.command == "diy":
            code = args.code if args.code is not None else input("Exact license code (English letters only): ")
            try:
                print(create_custom_license(db, code))
            except (ValueError, sqlite3.IntegrityError) as error:
                if isinstance(error, sqlite3.IntegrityError):
                    parser.error("license code already exists")
                parser.error(str(error))
        elif args.command == "list":
            print_licenses(list_licenses(db))
        elif args.command == "release":
            if not release_license(db, getpass.getpass("License key: ")):
                parser.error("license not found")
            print("Released")
    if args.command == "serve":
        with http.server.ThreadingHTTPServer(
            (args.host, args.port), make_handler(args.db)
        ) as server:
            print("Listening on {}:{}".format(args.host, args.port), flush=True)
            server.serve_forever()


if __name__ == "__main__":
    main()
