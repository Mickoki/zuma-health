"""Exercise the Godot client against the real Go server and a disposable SQLite DB.

Usage: python tests/run_real_server_integration.py GODOT_CONSOLE_EXE SERVER_EXE
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parent.parent


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def api(base, path, data=None):
    body = None if data is None else json.dumps(data).encode("utf-8")
    request = urllib.request.Request(base + path, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=2) as response:
        return json.load(response)


def run():
    godot, server = (str(Path(value).resolve()) for value in sys.argv[1:3])
    port = free_port()
    base = f"http://127.0.0.1:{port}"
    with tempfile.TemporaryDirectory(prefix="zuma-real-api-", dir=ROOT / ".godot") as tmp:
        env = os.environ.copy()
        env.update(ZUMA_ADDR=f"127.0.0.1:{port}", ZUMA_DB=str(Path(tmp) / "test.db"),
                   ZUMA_OLLAMA_URL="http://127.0.0.1:1", ZUMA_MODEL_TIMEOUT="2s")
        if os.name == "nt":
            env["APPDATA"] = tmp
        process = subprocess.Popen([server], env=env, cwd=tmp, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        try:
            for _ in range(100):
                if process.poll() is not None:
                    raise RuntimeError("Test server exited before becoming ready")
                try:
                    if api(base, "/readyz")["status"] == "ready":
                        break
                except (OSError, urllib.error.URLError):
                    time.sleep(0.1)
            else:
                raise RuntimeError("Test server did not become ready")
            profile = api(base, "/api/v1/profiles", {"display_name": "Synthetic test crew"})
            for day in (1, 2):
                payload = {
                    "client_session_id": str(uuid.uuid4()), "performed_at": f"2026-01-0{day}T12:00:00Z",
                    "protocol_version": "reaction-memory-v1", "source": "synthetic",
                    "survey": {"sleep_hours": 8, "fatigue": 0, "stress": 2, "mood": 7},
                    "reaction": {"trials": [{"outcome": "valid", "reaction_ms": 200 + day * 10}, {"outcome": "missed"}]},
                    "memory": {"correct": day + 1, "total": 4},
                }
                session = api(base, f"/api/v1/profiles/{profile['id']}/sessions", payload)
            env.update(ZUMA_TEST_API=base, ZUMA_TEST_SESSION_ID=session["id"], ZUMA_TEST_QUEUE_DIR=tmp,
                       ZUMA_TEST_PROFILE_ID=profile["id"])
            result = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script", "res://tests/client_integration.gd"],
                                    env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30)
            print(result.stdout, end="")
            print(result.stderr, end="", file=sys.stderr)
            output = result.stdout + result.stderr
            if result.returncode or "CLIENT INTEGRATION TEST PASSED" not in result.stdout or "ERROR:" in output:
                raise RuntimeError("Godot client verification failed")
            result = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script", "res://tests/minigames_real_server.gd"],
                                    env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30)
            print(result.stdout, end="")
            print(result.stderr, end="", file=sys.stderr)
            if result.returncode or "MINIGAMES REAL SERVER PASS" not in result.stdout or "ERROR:" in result.stdout + result.stderr:
                raise RuntimeError("Minigames integration verification failed")
            print("REAL SERVER INTEGRATION TEST PASSED")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
            if process.stdout:
                process.stdout.close()


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Expected paths to the Godot console executable and the server executable")
    run()
