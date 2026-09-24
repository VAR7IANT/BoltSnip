import concurrent.futures
import contextlib
import http.server
import os
import sqlite3
import subprocess
import sys
import tempfile
import threading
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "licensing"))
import server


def main():
    scratch = ROOT / "bin"
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=scratch) as folder:
        database = Path(folder) / "licenses.db"
        with contextlib.closing(server.connect(database)) as db:
            code = server.create_license(db)
            created = server.list_licenses(db)
            assert len(created) == 1 and created[0][1] == code
            assert created[0][2] is None
        httpd = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0), server.make_handler(database)
        )
        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()
        base = "http://127.0.0.1:{}".format(httpd.server_port)

        def post(route, device, key=code):
            payload = urllib.parse.urlencode({"key": key, "device": device}).encode()
            with urllib.request.urlopen(
                urllib.request.Request(base + route, data=payload), timeout=3
            ) as response:
                return response.read().decode()

        try:
            first, second = "a" * 64, "b" * 64
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                outcomes = list(
                    pool.map(lambda device: post("/activate", device), (first, second))
                )
            assert outcomes == ["OK", "OK"], outcomes
            states = [post("/check", first), post("/check", second)]
            assert sorted(states) == ["INACTIVE", "OK"], states
            winner = first if states[0] == "OK" else second
            loser = second if winner == first else first
            assert post("/check", winner) == "OK"
            assert post("/check", loser) == "INACTIVE"
            with contextlib.closing(server.connect(database)) as db:
                current = server.list_licenses(db)[0]
                assert current[2] == winner
                assert current[5] is not None
                assert current[6] == 1
            assert post("/activate", loser) == "OK"
            assert post("/check", winner) == "INACTIVE"
            assert post("/check", loser) == "OK"
            assert post("/activate", loser, "BS-invalid") == "INVALID"
            with contextlib.closing(server.connect(database)) as db:
                assert server.release_license(db, code)
            assert post("/check", loser) == "INACTIVE"
            assert post("/activate", winner) == "OK"
            environment = os.environ.copy()
            environment["BOLTSNIP_DB"] = str(database)
            listing = subprocess.run(
                [sys.executable, str(ROOT / "bsoio")],
                env=environment, text=True, capture_output=True, check=True
            ).stdout
            assert code in listing and "Transfers: 2" in listing
            new_code = subprocess.run(
                [sys.executable, str(ROOT / "bsoio"), "c"],
                env=environment, text=True, capture_output=True, check=True
            ).stdout.strip()
            assert new_code.startswith("BS-") and new_code != code
            diy_code = subprocess.run(
                [sys.executable, str(ROOT / "bsoio"), "d", "MyLicense"],
                env=environment, text=True, capture_output=True, check=True
            ).stdout.strip()
            assert diy_code == "MyLicense"
            with contextlib.closing(server.connect(database)) as db:
                assert len(server.list_licenses(db)) == 3
            assert post("/activate", "c" * 64, diy_code) == "OK"
            assert post("/check", "c" * 64, diy_code) == "OK"
            duplicate = subprocess.run(
                [sys.executable, str(ROOT / "bsoio"), "d", diy_code],
                env=environment, text=True, capture_output=True
            )
            assert duplicate.returncode != 0 and "already exists" in duplicate.stderr
            invalid = subprocess.run(
                [sys.executable, str(ROOT / "bsoio"), "d", "VIP01"],
                env=environment, text=True, capture_output=True
            )
            assert invalid.returncode != 0 and "English letters" in invalid.stderr
            assert post("/activate", "c" * 64, "不存在") == "INVALID"
            service = subprocess.Popen(
                [sys.executable, "-u", str(ROOT / "bsoio"), "s", "--port", "0"],
                env=environment, text=True, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            try:
                assert service.stdout.readline().startswith("Listening on 127.0.0.1:")
            finally:
                service.terminate()
                service.communicate(timeout=3)
            print("bsoio listing and code generation: PASS")
            print("License server automatic transfer and old-device revocation: PASS")
        finally:
            httpd.shutdown()
            httpd.server_close()
            thread.join(timeout=3)

        legacy = Path(folder) / "legacy.db"
        with contextlib.closing(sqlite3.connect(legacy)) as db:
            with db:
                db.execute(
                    "CREATE TABLE licenses (key_hash TEXT PRIMARY KEY, device TEXT, "
                    "created_utc TEXT NOT NULL DEFAULT (datetime('now')))"
                )
                db.execute(
                    "INSERT INTO licenses (key_hash) VALUES (?)",
                    (server.key_hash("BS-legacy"),)
                )
        with contextlib.closing(server.connect(legacy)) as db:
            old = server.list_licenses(db)[0]
            assert old[1] is None and old[6] == 0
            assert server.authorize(db, "BS-legacy", "c" * 64, True) == "OK"
        print("Legacy license database migration: PASS")


if __name__ == "__main__":
    main()
