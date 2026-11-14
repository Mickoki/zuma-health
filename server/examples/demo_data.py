"""Create a separate profile with fictional sessions for a Zuma demo."""
import json
import sys
import uuid
from datetime import datetime, timedelta, timezone
from urllib.request import Request, urlopen

base_url = sys.argv[1].rstrip('/') if len(sys.argv) > 1 else 'http://127.0.0.1:8080'


def post(path, data):
    request = Request(base_url + path, json.dumps(data).encode('utf-8'),
                      {'Content-Type': 'application/json'}, method='POST')
    with urlopen(request, timeout=10) as response:
        return json.load(response)


profile = post('/api/v1/profiles', {'display_name': 'Демо — участник экипажа'})
examples = [
    (2, 7.5, 4, 5, 6, [310, 290, 330], 3),
    (1, 8, 3, 4, 7, [290, 280, 300], 4),
    (0, 8.5, 2, 3, 8, [270, 260, 290], 4),
]
for days, sleep, fatigue, stress, mood, reaction, correct in examples:
    payload = {
        'client_session_id': str(uuid.uuid4()),
        'performed_at': (datetime.now(timezone.utc) - timedelta(days=days)).isoformat(),
        'protocol_version': 'reaction-memory-v1',
        'source': 'synthetic',
        'survey': {'sleep_hours': sleep, 'fatigue': fatigue, 'stress': stress, 'mood': mood},
        'reaction': {'trials': [{'outcome': 'valid', 'reaction_ms': ms} for ms in reaction]},
        'memory': {'correct': correct, 'total': 5},
    }
    post(f"/api/v1/profiles/{profile['id']}/sessions", payload)
print(f"Demo profile created: {profile['id']}. Refresh profiles in the app.")
