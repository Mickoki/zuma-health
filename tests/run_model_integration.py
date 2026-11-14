"""Check a locally installed Ollama model against the real Zuma server.

Run: python tests/run_model_integration.py PATH_TO_SERVER_EXE
Optional: --ollama-url http://127.0.0.1:11434 --model qwen3:8b
Uses a disposable database and synthetic data; never downloads a model.
"""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
from urllib.error import URLError
from urllib.parse import urlparse
from urllib.request import ProxyHandler, Request, build_opener
import uuid

ROOT = Path(__file__).resolve().parent.parent
HTTP = build_opener(ProxyHandler({}))


def request(base, path, payload=None, method=None, timeout=5):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {} if body is None else {"Content-Type": "application/json"}
    with HTTP.open(Request(base + path, data=body, headers=headers, method=method), timeout=timeout) as response:
        return json.load(response)


def loopback_url(value):
    parsed = urlparse(value)
    if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost", "::1"} or parsed.username or parsed.password or parsed.path not in {"", "/"} or parsed.query or parsed.fragment:
        raise ValueError("Ollama URL must be a local HTTP address without a path")
    if parsed.port is not None and not 1 <= parsed.port <= 65535:
        raise ValueError("Invalid Ollama port")
    return value.rstrip("/")


def run(server, ollama, model):
    version = request(ollama, "/api/version")
    tags = request(ollama, "/api/tags")
    if not version.get("version") or model not in [item.get("name") for item in tags.get("models", [])]:
        raise RuntimeError("Ollama is reachable, but the requested model is not installed")
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    base = f"http://127.0.0.1:{port}"
    with tempfile.TemporaryDirectory(prefix="zuma-model-check-") as tmp:
        env = os.environ.copy()
        env.update(ZUMA_ADDR=f"127.0.0.1:{port}", ZUMA_DB=str(Path(tmp) / "test.db"),
                   ZUMA_OLLAMA_URL=ollama, ZUMA_MODEL=model, ZUMA_MODEL_TIMEOUT="120s")
        process = subprocess.Popen([str(server)], cwd=tmp, env=env, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        try:
            for _ in range(100):
                if process.poll() is not None:
                    raise RuntimeError("Test server exited before becoming ready")
                try:
                    if request(base, "/readyz", timeout=1).get("status") == "ready":
                        break
                except (OSError, URLError):
                    time.sleep(0.1)
            else:
                raise RuntimeError("Test server did not become ready")
            profile = request(base, "/api/v1/profiles", {"display_name": "Synthetic model verification"})
            game = json.loads((ROOT / "server/examples/game_runs/pairs.json").read_text(encoding="utf-8"))
            game.update(client_run_id=str(uuid.uuid4()), source="synthetic",
                        performed_at=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                        survey={"sleep_hours": 8, "fatigue": 0, "stress": 2, "mood": 7})
            run = request(base, f"/api/v1/profiles/{profile['id']}/game-runs", game)
            path = f"/api/v1/game-runs/{run['id']}"
            outcome = request(base, path + "/explanation", method="POST", timeout=140)
            explanation = outcome.get("explanation") or {}
            if outcome.get("status") != "ready" or explanation.get("model") != model:
                raise RuntimeError("Model explanation was not accepted: " + str(outcome.get("status")))
            limitations = {fact["id"] for fact in explanation.get("limitations", [])}
            if not {"not_medical", "survey_timing", "synthetic", "no_baseline"}.issubset(limitations):
                raise RuntimeError("Required limitations are missing")
            report = request(base, path + "/report")
            if report.get("survey", {}).get("fatigue") != 0 or report.get("explanation") != explanation:
                raise RuntimeError("Survey or cached explanation did not survive the round trip")
            print(f"MODEL INTEGRATION PASS: {model}; synthetic game and survey; required limitations; cached report")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("server", type=Path)
    parser.add_argument("--ollama-url", default="http://127.0.0.1:11434")
    parser.add_argument("--model", default="qwen3:8b")
    args = parser.parse_args()
    try:
        run(args.server.resolve(strict=True), loopback_url(args.ollama_url), args.model)
    except (OSError, ValueError, RuntimeError, URLError) as exc:
        print(f"MODEL INTEGRATION NOT VERIFIED: {exc}", file=sys.stderr)
        sys.exit(1)
