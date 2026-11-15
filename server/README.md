# Zuma server

Local Go API for the Godot desktop client: surveys, reaction/memory tasks,
SQLite, history, JSON/HTML reports, and Qwen3 8B through Ollama. No wearable watch is used.
This is a prototype, not a medical system.

## Running on Windows / PowerShell

Go 1.26+ is required. No separate SQLite server or C compiler is needed. From `server`:

```powershell
go mod download
go run ./cmd/zuma
```

API: `http://127.0.0.1:8080`. The database `./data/zuma.db` is created automatically;
the path is relative to the process working directory. For explanations, first install
Ollama, download the model, and start Ollama if it is not already running:

```powershell
ollama pull qwen3:8b
ollama list
# If needed, in a separate terminal: ollama serve
```

Once dependencies and the model are downloaded and the build is complete, the workflow
does not require internet access. The core workflow does not require Ollama. Build and verify:

```powershell
go test ./...
go vet ./...
go build -o zuma.exe ./cmd/zuma
.\zuma.exe
```

Shutdown with Ctrl+C: cancel generation, shut down HTTP, and close SQLite.
The built binary runs without Go; Ollama and the model are installed separately.

## Settings

| Variable | Default |
| --- | --- |
| ZUMA_ADDR | 127.0.0.1:8080 |
| ZUMA_DB | ./data/zuma.db |
| ZUMA_OLLAMA_URL | http://127.0.0.1:11434 |
| ZUMA_MODEL | qwen3:8b |
| ZUMA_MODEL_TIMEOUT | 120s; positive, maximum 10m |

Example: `$env:ZUMA_DB = 'C:\ZumaData\zuma.db'` before starting.
The listener accepts only loopback IPs or localhost. Ollama uses local HTTP without
proxies, external redirects, or a model with the `:cloud` suffix. The target model is qwen3:8b.

The unauthenticated API is intended for a trusted local desktop client.
Profiles do not isolate data between OS processes. CORS is disabled. Network,
browser, and multi-user access require separate design work.
The database is unencrypted: the OS controls access to its directory.

## API and Godot

Independent runs of the four new games use `/game-runs`,
without requiring the legacy survey/reaction/memory session. [Contract and examples](docs/minigames.md),
[portable Godot module](../addons/zuma_minigames/README.md). SQLite automatically
migrates to schema2; stop the old server and back up the database before upgrading.

- [OpenAPI 3.1](docs/openapi.yaml): paths, schemas, statuses, limits.
- [GDScript](examples/client.gd): asynchronous Godot 4 desktop example.
- [PowerShell](examples/requests.ps1): complete synthetic workflow.

In another terminal, from `server`:

```powershell
Invoke-RestMethod http://127.0.0.1:8080/readyz
.\examples\requests.ps1
.\examples\requests.ps1 -Explain
```

curl (for example, from Git Bash):

```sh
curl -X POST http://127.0.0.1:8080/api/v1/profiles -H 'Content-Type: application/json' -d '{"display_name":"Demo crew member"}'
```

Sequence: POST profile → POST complete session → GET history → GET report →
optional POST explanation → GET report again. HTML:
`/api/v1/sessions/{id}/report.html`. Use the browser to print/save it as PDF;
there is no separate PDF endpoint.

The client retains the client_session_id UUID with the payload until a successful response:
201 means a new session, 200 an identical replay, and 409 different data with the same UUID.
A new task run needs a new UUID. Drafts are stored in Godot; the server accepts
a complete session with the survey and both tasks. Explanation requests use a separate
HTTPRequest with a 140-second timeout against the server's 120 seconds.

## Calculations

Survey: sleep_hours 0–24 h; fatigue/stress 0–10 (higher means more), mood 0–10
(higher means better). These are product scales without clinical validation. Zeros are valid;
missing fields and null are not replaced with zeros.

Reaction: 1–200 valid/premature/missed attempts; reaction_ms 1–10000 ms only
for valid attempts. Mean and median use valid attempts; without any, both are null. Memory: correct/total*100,
1<=total<=1000. reaction-memory-v1 provides task comparability;
changing the mechanics requires a new agreed protocol version.

The baseline is the nearest strictly earlier session with the same profile, protocol,
and source. Upload order does not matter. Comparisons cover the median (ms and percent),
memory (percentage points), and self-assessment. Backfilled sessions can change the baseline:
the old explanation is hidden. synthetic and observed are kept separate.
History is sorted by performed_at and ID, newest first, with limit/offset pagination.

Qwen selects and orders allowed fact_ids; Go validates categories,
references, and structure and produces text using its own numbers. Arbitrary model text
is not published. Go adds mandatory limitations. This explains facts rather than providing
open-ended advice; the model may choose a less useful order.
There are no diagnoses, clinical thresholds, or overall “health score”.

Only one generation runs at a time; another request receives 409. HTTP 200 contains
status ready/unavailable/invalid, which the client must check. Failure does not remove
an existing current explanation. Saving and numeric reports do not depend on the model.
/healthz checks the process; /readyz checks SQLite; /api/v1/model/status checks Ollama and model availability.

## Backup

Data, WAL files, builds, and model weights are excluded from Git. For a backup, stop
the server and every other process with the database open. Copy the directory containing zuma.db and,
if present, zuma.db-wal and zuma.db-shm together as one set. Simply copying
a running database is unsuitable. To restore, with the server stopped,
restore the entire set into a separate empty directory, set ZUMA_DB, start the server,
and check the history. Do not combine WAL files from different backups.

Migrations are embedded, transactional, and run at startup. An older server
rejects a newer schema. Back up before upgrading.
Verification results: [verification.md](docs/verification.md).
