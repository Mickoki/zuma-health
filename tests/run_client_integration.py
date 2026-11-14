"""Run: python tests/run_client_integration.py PATH_TO_GODOT_CONSOLE_EXE"""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import parse_qs, urlparse

PROFILE = "a" * 32
SESSION = "b" * 32
BASELINE = "d" * 32
session_requests = []
profile_mode = "normal"
history_mode = "normal"
fail_next_send = False
delay_next_send = False
latest_mode = "normal"
malformed_next_send = False
delay_next_trend = False
fail_trend_report_once = False
slow_trend_reports = False
active_trend_reports = 0
peak_trend_reports = 0
trend_report_lock = threading.Lock()

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, value):
        body = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass

    def do_GET(self):
        global profile_mode, history_mode, fail_next_send, delay_next_send, latest_mode, malformed_next_send, delay_next_trend, fail_trend_report_once, slow_trend_reports, active_trend_reports, peak_trend_reports
        if self.path == "/test/slow_profiles":
            profile_mode = "slow"
            self.reply({"ok": True})
            return
        if self.path == "/test/paged_history":
            history_mode = "paged"
            self.reply({"ok": True})
            return
        if self.path == "/test/trend_data":
            history_mode = "trend"
            self.reply({"ok": True})
            return
        if self.path == "/test/delay_next_trend":
            delay_next_trend = True
            self.reply({"ok": True})
            return
        if self.path == "/test/fail_trend_report":
            fail_trend_report_once = True
            self.reply({"ok": True})
            return
        if self.path == "/test/slow_trend_reports":
            slow_trend_reports = True
            with trend_report_lock:
                peak_trend_reports = 0
            self.reply({"ok": True})
            return
        if self.path == "/test/trend_report_stats":
            with trend_report_lock:
                self.reply({"peak": peak_trend_reports, "active": active_trend_reports})
            return
        if self.path == "/test/fail_next_send":
            fail_next_send = True
            self.reply({"ok": True})
            return
        if self.path == "/test/delay_next_send":
            delay_next_send = True
            self.reply({"ok": True})
            return
        if self.path == "/test/latest_race":
            latest_mode = "race"
            history_mode = "normal"
            self.reply({"ok": True})
            return
        if self.path == "/test/malformed_next_send":
            malformed_next_send = True
            self.reply({"ok": True})
            return
        if self.path.startswith("/api/v1/profiles?"):
            profiles = [{"id": PROFILE, "display_name": "Test crew"}]
            if profile_mode == "slow":
                time.sleep(0.3)
                profiles.append({"id": "c" * 32, "display_name": "Another crew"})
            self.reply({"items": profiles, "total": len(profiles)})
        elif self.path.startswith(f"/api/v1/profiles/{PROFILE}/sessions?"):
            if delay_next_trend and "limit=100&" in self.path:
                delay_next_trend = False
                time.sleep(0.4)
            if latest_mode == "race" and "limit=1&" in self.path:
                time.sleep(0.4)
            if history_mode == "trend":
                items = [
                    {"id": "1" * 32, "performed_at": "2026-01-06T12:00:00Z", "source": "observed", "protocol_version": "reaction-memory-v1", "survey": {"sleep_hours": None, "fatigue": 2, "stress": 1, "mood": 5}},
                    {"id": "2" * 32, "performed_at": "2026-01-05T12:00:00Z", "source": "synthetic", "protocol_version": "reaction-memory-v1", "survey": {"sleep_hours": 11, "fatigue": 1, "stress": 2, "mood": 3}},
                    {"id": "3" * 32, "performed_at": "2026-01-04T12:00:00Z", "source": "observed", "protocol_version": "reaction-memory-v2", "survey": {"sleep_hours": 4, "fatigue": 3, "stress": 2, "mood": 1}},
                    {"id": "4" * 32, "performed_at": "2026-01-03T12:00:00Z", "source": "observed", "protocol_version": "reaction-memory-v1", "survey": {"sleep_hours": 8, "fatigue": 5, "stress": 4, "mood": 6}},
                    {"id": "5" * 32, "performed_at": "2026-01-01T12:00:00Z", "source": "observed", "protocol_version": "reaction-memory-v1", "survey": {"sleep_hours": 0, "fatigue": 0, "stress": 1, "mood": 7}},
                ]
                for item in items:
                    item["memory"] = {"correct": 3, "total": 4}
                params = parse_qs(urlparse(self.path).query)
                offset, limit = int(params["offset"][0]), int(params["limit"][0])
                self.reply({"items": items[offset:offset + limit], "total": len(items), "offset": offset, "limit": limit})
            elif history_mode == "paged":
                params = parse_qs(urlparse(self.path).query)
                offset = int(params["offset"][0])
                limit = int(params["limit"][0])
                items = [{"id": f"{i:032x}", "performed_at": f"2026-01-{i + 1:02}T12:00:00Z", "source": "synthetic", "protocol_version": "reaction-memory-v1", "survey": {"sleep_hours": 8, "fatigue": 0, "stress": 2, "mood": 7}, "memory": {"correct": 3, "total": 4}} for i in range(23)]
                self.reply({"items": items[offset:offset + limit], "total": len(items), "offset": offset, "limit": limit})
            else:
                self.reply({"items": [{"id": SESSION, "performed_at": "2026-01-02T12:00:00Z", "source": "synthetic", "protocol_version": "reaction-memory-v1", "survey": {"sleep_hours": 8, "fatigue": 0, "stress": 2, "mood": 7}, "memory": {"correct": 3, "total": 4}}], "total": 1})
        elif self.path.startswith(f"/api/v1/profiles/{'c' * 32}/sessions?"):
            self.reply({"items": [], "total": 0})
        elif self.path == f"/api/v1/sessions/{SESSION}/report":
            self.reply({"performed_at": "2026-01-02T12:00:00Z", "source": "synthetic", "baseline_session_id": BASELINE, "reaction": {"median_ms": 230, "valid": 2, "premature": 0, "missed": 1}, "memory_percent": 75, "survey": {"sleep_hours": 8, "fatigue": 0, "stress": 2, "mood": 7}, "comparison": {"memory_delta_pp": 5, "reaction_delta_ms": -10, "survey_delta": {"sleep_hours": -1, "fatigue": 1, "stress": 0, "mood": -2}}, "explanation": None})
        elif self.path == f"/api/v1/sessions/{BASELINE}/report":
            self.reply({"performed_at": "2026-01-01T12:00:00Z", "source": "synthetic", "baseline_session_id": None, "reaction": {"median_ms": None, "valid": 0, "premature": 1, "missed": 1}, "memory_percent": 50, "survey": {"sleep_hours": 9, "fatigue": 0, "stress": 2, "mood": 9}, "comparison": None, "explanation": None})
        elif self.path.startswith("/api/v1/sessions/") and self.path.endswith("/report"):
            session_id = self.path.split("/")[-2]
            values = {"1": (75, None, "observed", "reaction-memory-v1"),
                      "2": (90, 500, "synthetic", "reaction-memory-v1"),
                      "3": (40, 600, "observed", "reaction-memory-v2"),
                      "4": (80, 250, "observed", "reaction-memory-v1"),
                      "5": (60, 300, "observed", "reaction-memory-v1"),
                      "6": (61, 301, "observed", "reaction-memory-v1"),
                      "7": (62, 302, "observed", "reaction-memory-v1"),
                      "8": (63, 303, "observed", "reaction-memory-v1"),
                      "9": (64, 304, "observed", "reaction-memory-v1"),
                      "a": (65, 305, "observed", "reaction-memory-v1")}
            key = session_id[0] if len(session_id) == 32 and session_id == session_id[0] * 32 else ""
            slow = slow_trend_reports and key in values
            if slow:
                with trend_report_lock:
                    active_trend_reports += 1
                    peak_trend_reports = max(peak_trend_reports, active_trend_reports)
                time.sleep(0.35)
            if key not in values:
                self.send_error(404)
            elif key == "4" and fail_trend_report_once:
                fail_trend_report_once = False
                self.send_error(503)
            else:
                memory, median, source, protocol = values[key]
                self.reply({"session_id": session_id, "source": source, "protocol_version": protocol, "memory_percent": memory, "reaction": {"median_ms": median}})
            if slow:
                with trend_report_lock:
                    active_trend_reports -= 1
        else:
            self.send_error(404)

    def do_POST(self):
        global fail_next_send, delay_next_send, malformed_next_send
        if self.path == f"/api/v1/sessions/{SESSION}/explanation":
            self.reply({"status": "unavailable", "explanation": None})
        elif self.path == f"/api/v1/profiles/{PROFILE}/sessions":
            payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            session_requests.append(payload)
            if delay_next_send:
                delay_next_send = False
                time.sleep(0.4)
            if malformed_next_send:
                malformed_next_send = False
                body = b"<html>unexpected response</html>"
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            elif len(session_requests) == 1 or fail_next_send:
                fail_next_send = False
                self.send_error(503)
            else:
                self.reply({"id": SESSION, "profile_id": PROFILE, "client_session_id": payload["client_session_id"]})
        else:
            self.send_error(404)

if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env = os.environ.copy()
    env["ZUMA_TEST_API"] = f"http://127.0.0.1:{server.server_port}"
    try:
        with tempfile.TemporaryDirectory(prefix="zuma-queue-test-", dir=root / ".godot") as queue_dir:
            env["ZUMA_TEST_QUEUE_DIR"] = queue_dir
            for script, marker in (("client_integration.gd", "CLIENT INTEGRATION TEST PASSED"),
                                   ("session_queue_integration.gd", "SESSION QUEUE TEST PASSED"),
                                   ("game_flow.gd", "GAME FLOW TEST PASSED"),
                                   ("profile_race.gd", "PROFILE RACE TEST PASSED"),
                                   ("history_pagination.gd", "HISTORY PAGINATION TEST PASSED"),
                                   ("home_latest.gd", "HOME LATEST TEST PASSED"),
                                   ("queue_health.gd", "QUEUE HEALTH TEST PASSED"),
                                   ("trends.gd", "TRENDS TEST PASSED"),
                                   ("trend_loader.gd", "TREND LOADER TEST PASSED"),
                                   ("help_page.gd", "HELP PAGE TEST PASSED")):
                result = subprocess.run([sys.argv[1], "--headless", "--path", str(root), "--script", "res://tests/" + script], env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30)
                print(result.stdout, end="")
                print(result.stderr, end="", file=sys.stderr)
                output = result.stdout + result.stderr
                if result.returncode or marker not in result.stdout or "SCRIPT ERROR" in output or "ERROR:" in output:
                    sys.exit(1)
            if len(session_requests) != 7 or session_requests[0] != session_requests[1] or session_requests[2] != session_requests[3] or session_requests[5] != session_requests[6]:
                sys.exit("Retry did not preserve the original payload")
    finally:
        server.shutdown()
        server.server_close()
