"""Check demo_data.py against an isolated local API stub."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys
import threading

requests = []


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        requests.append((self.path, data))
        response = {'id': 'demo-profile', 'display_name': data['display_name']} if self.path == '/api/v1/profiles' else {'id': 'demo-session'}
        body = json.dumps(response).encode()
        self.send_response(201)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    script = Path(__file__).resolve().parent.parent / 'server' / 'examples' / 'demo_data.py'
    subprocess.run([sys.executable, str(script), f'http://127.0.0.1:{server.server_port}'], check=True, timeout=20)
    assert len(requests) == 4
    sessions = requests[1:]
    assert all(path == '/api/v1/profiles/demo-profile/sessions' and data['source'] == 'synthetic' for path, data in sessions)
    assert len({data['client_session_id'] for _, data in sessions}) == 3
    assert all(len(data['reaction']['trials']) == 3 for _, data in sessions)
    print('DEMO DATA TEST PASSED')
finally:
    server.shutdown()
    server.server_close()
