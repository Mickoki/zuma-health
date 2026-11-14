"""Capture history/report with synthetic mock data: python tests/capture_mock_screens.py GODOT_EXE"""
import os
from http.server import ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys
import threading
import urllib.request

from run_client_integration import Handler

root = Path(__file__).resolve().parent.parent
server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
env = os.environ.copy()
env["ZUMA_TEST_API"] = f"http://127.0.0.1:{server.server_port}"
startup = subprocess.STARTUPINFO()
startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
startup.wShowWindow = 0
try:
    captures = [(name, name, None) for name in ("home", "history", "report", "queue_warning", "trends")]
    captures.append(("trends", "trends-small", "960x540"))
    captures.append(("trend-reaction", "trend-reaction", None))
    captures.append(("trend-memory", "trend-memory", "960x540"))
    for page, output_name, resolution in captures:
        if page.startswith("trend"):
            with urllib.request.urlopen(env["ZUMA_TEST_API"] + "/test/trend_data", timeout=2) as response:
                response.read()
        env["ZUMA_CAPTURE_PAGE"] = page
        env["ZUMA_CAPTURE_PATH"] = str(root / ".godot" / f"capture-{output_name}.png")
        command = [sys.argv[1], "--path", str(root)]
        if resolution:
            command.extend(["--resolution", resolution])
        command.extend(["--script", "res://tests/capture_ui.gd"])
        result = subprocess.run(command,
                                env=env, startupinfo=startup, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=30)
        print(result.stdout, end="")
        print(result.stderr, end="", file=sys.stderr)
        if result.returncode or "ERROR:" in result.stdout + result.stderr or not Path(env["ZUMA_CAPTURE_PATH"]).exists():
            sys.exit(1)
finally:
    server.shutdown()
    server.server_close()
