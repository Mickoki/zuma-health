"""Test the optional model probe with a local fake Ollama (not a real model)."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import sys
import threading

ROOT = Path(__file__).resolve().parent.parent


class FakeOllama(BaseHTTPRequestHandler):
    saw_survey = False
    installed = True

    def log_message(self, *args):
        pass

    def send_json(self, value):
        data = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/api/version":
            self.send_json({"version": "test-only"})
        elif self.path == "/api/tags":
            self.send_json({"models": [{"name": "qwen3:8b"}] if self.installed else []})
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path != "/api/chat":
            self.send_error(404)
            return
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        prompt = body["messages"][-1]["content"]
        type(self).saw_survey = '"id":"survey"' in prompt and '"id":"survey_timing"' in prompt
        self.send_json({"done": True, "message": {"role": "assistant", "content":
                        '{"observations":["survey"],"comparisons":[],"limitations":[]}'}})


def main():
    server_exe = str(Path(sys.argv[1]).resolve(strict=True))
    fake = ThreadingHTTPServer(("127.0.0.1", 0), FakeOllama)
    threading.Thread(target=fake.serve_forever, daemon=True).start()
    cmd = [sys.executable, str(ROOT / "tests/run_model_integration.py"), server_exe,
           "--ollama-url", f"http://127.0.0.1:{fake.server_port}"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30)
        if result.returncode or "MODEL INTEGRATION PASS" not in result.stdout or not FakeOllama.saw_survey:
            raise RuntimeError(result.stdout + result.stderr)
        FakeOllama.installed = False
        missing = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=10)
        if missing.returncode == 0 or "not installed" not in missing.stderr:
            raise RuntimeError("Missing model was not reported: " + missing.stdout + missing.stderr)
        print("MODEL PROBE HARNESS PASS (fake Ollama; not real-model verification)")
    finally:
        fake.shutdown()
        fake.server_close()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Expected path to the server executable")
    main()
