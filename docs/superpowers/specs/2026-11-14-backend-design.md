# Zuma: a single local server

Date: 2026-11-14. Status: approved by the user on 2026-11-14.

## Purpose and scope

Create Zuma's backend for the NASA Space Apps astronaut health monitoring
project. The Godot client submits self-reports and task results; the server
stores history, calculates descriptive measures, and produces a report.
Qwen3 8B through Ollama explains results that have already been calculated.

Agreed with the user: Go, a single server, SQLite, local Qwen3 8B through
Ollama; watch integration is excluded. The other concrete decisions below
were proposed by the implementer and are subject to this document's approval.

Deliverables include code, migrations, an API contract, Godot examples,
startup instructions, automated tests, and verification with the installed
model. UI and minigame development, cloud hosting, remote access, medical
diagnosis, and model training are outside this implementation's scope.

Losing saved sessions on model errors, replacing missing data with zeros,
mixing real and demonstration results, publishing arbitrary model text,
invented measurements, or medical conclusions are prohibited.

## Approaches considered

1. A single Go process: HTTP API, calculations, SQLite, reports, and an Ollama
   adapter. Minimal components for local use; the model remains a separate
   local process. Selected by the user.
2. Separate API and generation services: independent scaling and queues,
   but additional processes and coordination for a local prototype.
   Not selected.

## Components and startup

Code resides in `server/`, a separate Go module. Standard `net/http`,
`database/sql`, SQLite through `modernc.org/sqlite`, HTML through `html/template`.
Dependency versions are pinned in go.mod/go.sum. Separation: entry point,
configuration, HTTP handlers, domain types and calculations, storage,
Ollama client, report template. Exact package names are left to the implementer.

Defaults: `127.0.0.1:8080`, database `./data/zuma.db`, Ollama
`http://127.0.0.1:11434`, model `qwen3:8b`. Configuration uses environment
variables with documented values and validation at startup.
The server is designed for a trusted local desktop client without authentication.
Binding to a nonlocal interface is prohibited in this version; CORS is not
allowed by default, so a browser client requires a separate decision.
Profiles separate history but are not a security boundary between OS users.
Any local process with API access can read the data.

Installing dependencies and initially downloading the model may require network
access. After building the server and downloading the model, the workflow runs
offline. The server also starts without Ollama. Provide graceful HTTP shutdown,
generation cancellation, and database closing. Logs contain neither survey
bodies nor model text.

## Data and lifecycle

The server generates opaque random string identifiers. All server timestamps
are UTC in RFC3339. Input `performed_at` is required RFC3339 with a timezone;
server receipt time is stored separately. Times more than 5 minutes in the
future are rejected. History sorts by performed_at, then ID.

- **Profile:** id, display_name (1–100 characters), created_at.
- **Session:** id, profile_id, client_session_id, performed_at, received_at,
  protocol_version (`reaction-memory-v1`), source (`observed` or `synthetic`),
  self-report, raw results, calculation version.
- **Self-report:** sleep_hours (0–24), fatigue (0–10), stress (0–10),
  mood (0–10, higher is better). Every field is required. The scales form a
  product survey, not a validated clinical instrument. No free text yet.
- **Reaction:** trials array (1–200), each containing outcome
  (`valid`, `premature`, `missed`); reaction_ms is required only for valid
  and must be a finite number from 1 to 10000. It is absent for other
  outcomes. Units: milliseconds.
- **Memory:** correct and total are integers, 1 <= total <= 1000,
  0 <= correct <= total. This is the proportion of correct answers, without
  assuming specific game mechanics.
- **Explanation:** session_id, status (`ready`, `unavailable`, `invalid`),
  input report version and baseline_session_id, model, time, validated
  response structure; technical error text is not exposed externally.

The survey and both tasks are saved in one transaction. Incomplete incoming
sessions are rejected; drafts remain in Godot. A saved session is immutable.
For retries, Godot generates a UUID in client_session_id, unique within a
profile. A semantically identical request returns the existing session;
different data with the same key returns 409. JSON key order is irrelevant.

SQLite stores profiles, sessions, and explanations; raw results may be stored
as validated JSON within the session row. Indexes cover profile, time, and
retry key; foreign keys are enabled. Migrations are embedded in the binary,
applied transactionally, and record the schema version. Configure busy timeout,
WAL, and connection limits. Data, WAL, builds, and model weights are excluded
from Git. Tests use temporary databases. Documentation describes backup with
the server stopped, including SQLite files, and restoration from that backup.

## Calculations and comparison

Calculation version `v1`. The server returns valid/premature/missed counts,
mean and median reaction_ms for valid trials, and memory correct-answer
percentage correct / total * 100. Without valid trials, mean and median are
null. Survey measures are returned with scale names and units.

Baseline is the nearest strictly earlier session for the same profile with
the same protocol_version and source; equal performed_at is not earlier.
Upload order does not affect selection. Reaction uses the median difference
in ms, memory the difference in percentage points, and the survey differences
by field. Relative median change in percent is returned when both medians
exist. Without a baseline, return null and an explicit explanation. Real and
synthetic data are compared separately. Changing the task protocol requires
a new version, so the client must submit the current version.

This describes task performance: no universal “health score”, clinical
thresholds, diagnosis, or fitness-for-duty conclusion. If a more suitable
baseline is backfilled, recalculate the report and do not show an explanation
saved for old input data as current.

## HTTP API

All request bodies and responses are UTF-8 JSON except the HTML report.
Prefix: `/api/v1`. The final OpenAPI specification contains exact schemas
and examples.

| Method and path | Behavior |
| --- | --- |
| GET /healthz | 200 while the process is running; no model call |
| GET /readyz | SQLite readiness; 503 on error, independent of Ollama |
| GET /api/v1/model/status | Time-limited check of Ollama and model availability |
| POST /api/v1/profiles | Create profile, 201 |
| GET /api/v1/profiles | Profile list with limit/offset |
| GET /api/v1/profiles/{id} | Profile or 404 |
| POST /api/v1/profiles/{id}/sessions | Atomic save, 201; retry — 200 |
| GET /api/v1/profiles/{id}/sessions | History with limit/offset, newest first |
| GET /api/v1/sessions/{id} | Raw data and metadata |
| GET /api/v1/sessions/{id}/report | Numerical report and current explanation, if any |
| GET /api/v1/sessions/{id}/report.html | Escaped HTML for viewing and printing |
| POST /api/v1/sessions/{id}/explanation | Separate time-limited generation |

Pagination: default limit 20, maximum 100, offset >= 0.
List shape: `{items, limit, offset, total}`. An unknown profile returns 404;
an existing profile without sessions returns an empty list.
Shared error contract: `{error: {code, message, fields?}}`.
400 — invalid JSON/parameters; 413 — body larger than 256 KiB;
415 — wrong Content-Type for a JSON body; 422 — domain schema violation;
404 — missing resource; 409 — retry conflict or busy generation;
500/503 — internal failure/storage not ready without leaking details.
Reject unknown fields, extra JSON values, nonfinite numbers, missing required
fields (including those allowing zero), unsupported protocols, and invalid IDs.

## Qwen3 8B and factual accuracy

The adapter calls local `POST /api/chat`: model `qwen3:8b`, stream false,
think false, temperature 0, bounded response length, default timeout 120 seconds.
At most one generation runs at once; additional requests receive 409. Normal
API requests continue working. The Godot client must allocate a separate
HTTPRequest for explanations with a timeout longer than the server's.

The prompt includes only the calculated report, baseline, and scale descriptions,
without display_name or other identifying data. Output uses JSON Schema with
three fact_ids arrays: observations (current results), comparisons, and
limitations. The server prepares allowed facts from the report with stable IDs
and categories; Qwen selects and orders facts. Go validates references and
categories and builds the explanation in Russian using its own dictionary,
without publishing the model's free text. Each fact is an independent descriptive
statement, so ordering does not create causal claims.

Validation of JSON, length, allowed fact_ids, categories, duplicates, and absence
of additional fields is mandatory. At least one observation is required; Go
adds all mandatory limitations (synthetic source, missing baseline/valid reaction,
nonmedical nature of results) regardless of model selection. The model cannot
produce diagnoses or treatment recommendations in published text: the contract
has no free-text field. Invalid output is not published. The numerical report
is always available. Explicitly state the approach's limitation: this is an
explanation based on selection of validated facts, not free-form medical advice;
the model may choose a less useful order but cannot change fact values.

Generation returns 200 with `{status, explanation, reason?}`: ready on success,
unavailable on timeout/model unavailability, invalid for unacceptable output.
Only a validated ready explanation is stored, with an input fingerprint;
a failed retry does not destroy an already-saved current explanation.
Cancelling the request also cancels the Ollama call. Server restart does not
require queue recovery: this version has no persistent background jobs.

## Documentation and readiness verification

Update README.md and PLAN.md to reflect actual state, removing watches from
the current architecture. Add OpenAPI, curl/PowerShell examples, and a separate
GDScript example covering the survey, saving, history, report, and explanation.
Do not create the missing game scenes within the backend task.

Required checks:

- Calculations with known values, no valid trials, no baseline, incompatible
  protocols/sources, and performed_at ordering;
- SQLite: migrations, constraints, atomicity, retries, persistence after closing
  and reopening;
- HTTP: complete workflow from profile to both report formats, pagination,
  validation errors, empty/unknown resources, HTML escaping;
- Mock Ollama: success, invalid JSON/facts, timeout, unavailability, busy state,
  cancellation; none of these failures disrupt saving or reporting;
- gofmt, go vet, go test, and a Windows binary build;
- Real API launch on a temporary database and a local qwen3:8b request for an
  explicitly synthetic session; a separate complete-workflow check with an
  unreachable Ollama address and external server network access disabled
  through test configuration/controlled transport without changing OS settings.

Evidence and limitations are recorded in the final verification report.
A failed model launch is not replaced by a mock test: state the cause, and leave
real integration unconfirmed until a successful check.

## Implementer decisions

Exact package and OpenAPI field names, SQL structure within the described model,
HTTP timeout settings, ID format, canonical payload encoding for idempotency,
HTML formatting, and helper scripts are chosen by the implementer. They must
preserve this specification's behavior and constraints.
