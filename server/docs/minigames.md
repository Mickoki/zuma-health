# Independent minigame API

The `/api/v1` extension does not change the legacy `/sessions`: the survey and legacy reaction/memory
tasks are not required for the new games. A new run may include an optional copy of the saved
`survey`; the main application requires saving the survey before playing. Older records without
a survey remain available. Survey completion time is not stored. The complete schema and four
synthetic examples are in [OpenAPI](openapi.yaml); JSON files are in [examples/game_runs](../examples/game_runs/).

## Paths

| Method / path | Purpose |
| --- | --- |
| POST /profiles/{profile_id}/game-runs | 201 new record, 200 identical replay, 409 changed payload for the same UUID |
| GET /profiles/{profile_id}/game-runs?game_id=pairs&limit=20&offset=0 | History of all outcomes; game_id filter is optional |
| GET /game-runs/{id} | Original data and server metadata |
| GET /game-runs/{id}/report | Numeric metrics, comparison, limitations, and current explanation |
| GET /game-runs/{id}/report.html | Escaped HTML for printing |
| POST /game-runs/{id}/explanation | Separate ready/unavailable/invalid generation with no request body |

All paths in the table have the `/api/v1` prefix. Profiles are created through the existing
POST /api/v1/profiles. Unknown profiles return 404; malformed IDs return 400.
Limits: new POST 1 MiB / 10000 events / 24 hours; legacy requests remain limited to 256 KiB.
Malformed JSON returns 400, media type 415, exceeded limits 413, and semantically invalid runs 422.

## Envelope and events

The optional survey field is an object with four values (sleep 0–24, others 0–10);
it is included in the immutable payload and replay checks.

Required fields: client_run_id (client UUID), game_id (fifteen/pairs/math/chimp),
rules_version=1, difficulty (easy/normal/hard), config, source (observed/synthetic),
performed_at (start time in RFC3339), status (completed/failed/aborted), finish_reason,
duration_ms, initial, events. All numeric inputs are integers; null is not zero.
Configuration must exactly match the selected level; unknown fields/versions
and extra events are rejected. t_ms values must be nondecreasing and within the duration.
The final event `{kind:"finish", t_ms:duration_ms}` is required.

| Game | initial | Events before finish |
| --- | --- | --- |
| fifteen | board[16] containing 0–15, scramble containing shuffle move indices | move: tile index 0–15 |
| pairs | cards: each symbol 0…pairs-1 exactly twice | flip: card index |
| math | questions[20]: op/add/sub/mul/div, a, b, options[4] | show: question index 0–19; answer: option index 0–3; skip; timeout |
| chimp | {} | show: positions, cell indices in number order; click: cell index 0–39 |

Every event has kind and t_ms. show/math has no positions; show/chimp
has no index. skip/timeout/finish have no extra fields. The first show/math
and show/chimp have t_ms=0. The client measures durations with a monotonic clock;
the server checks consistency. This does not prove that a real measurement took place.

Config:

- fifteen: shuffle_moves=30/90/180.
- pairs: pairs=9/12/18, preview_ms=5000/4000/3000, mismatch_ms=700.
- math: question_count=20, time_limit_ms=60000, question_limit_ms=8000/6000/4000.
- chimp: columns=8, rows=5, start_count=5/6/9, target_count=12/18/24, mistake_limit=4/3/2.

Math: easy has 10 add/10 sub, operands 0–30; normal has 7 add/7 sub with 0–75
and 6 mul with 0–18; hard has 5 of each operator, add/sub 0–150, mul 2–30,
and div with divisor 2–18 and quotient 2–30. Subtraction is nonnegative; division is exact.
Options are unique, within -1000…1000, with exactly one correct answer. Pool sizes are 992/6042/23880;
commuted addition/multiplication share one key, and questions do not repeat within a game.

Late answer events are rejected: the deadline boundary belongs to timeout.
A timeout may be recorded later because of a delayed frame, but never before the deadline.
An unfinished overdue question cannot be hidden by marking the whole game aborted.
20 resolved questions finish with questions_done; expiry of the overall time finishes with
time_limit, even with zero correct answers. Future questions that were never shown
are not included in skipped.

## Storage, comparison, and model

After validation, the server saves the original event log atomically. UUIDs are unique within
a profile across all game_id values. Object keys and UTC representations are normalized;
a replay does not create a record. Calculations are reproduced from the original events.

A report contains metrics and units. Missing required data produces null, not 0.
accuracy_percent uses complete pair attempts / accepted math answers.
Times are in ms; correct_per_minute is correct answers / total duration * 60000.
Chimp reports the largest successfully completed size, or null when there were no successes.

The baseline is the nearest strictly earlier comparable run with the same
profile, game, version, difficulty, config, and source. For the first three games it must be
completed; chimp wins are compared with wins, and mistake-limit failures with
the same outcome. Aborted runs are not compared but remain visible in history. Deltas equal current
values minus baseline; accuracy changes use percentage points. Fifteen Puzzle shuffles
do not guarantee equal optimal distances, so comparisons are descriptive.

SQLite migration 1→2 adds game_runs/game_run_explanations and indexes,
without changing legacy tables or data. Before upgrading, stop the old server
and make a full backup of its SQLite directory. The old binary cannot open schema2;
rollback requires a backup, not manually lowering user_version.

Qwen3:8b through Ollama selects only allowed fact_ids; Go produces the text and numbers.
The server adds source/client_timing/not_medical limitations.
If a survey is linked to the game, the server adds its validated values to the allowed
observations and always states that survey completion time is unknown.
This fact is unavailable for older runs without a survey. A previously saved
explanation with a different set of limitations is considered outdated and may
be requested again; numeric results are retained.
The generation slot is shared with the legacy API: a concurrent request receives 409.
The numeric report does not invoke the model and is available without it. The fingerprint includes
the baseline and current fact wording, so backfills or wording changes hide outdated explanations.
Failure does not erase a ready, current explanation. The endpoint can wait up to 120 s;
the client needs a longer timeout, such as 140 s.

## PowerShell example

From server, with the server running:

```powershell
$base = 'http://127.0.0.1:8080'
$profile = Invoke-RestMethod -Method Post "$base/api/v1/profiles" -ContentType 'application/json' -Body '{"display_name":"Synthetic game demo"}'
$payload = Get-Content -LiteralPath examples/game_runs/pairs.json -Raw
$run = Invoke-RestMethod -Method Post "$base/api/v1/profiles/$($profile.id)/game-runs" -ContentType 'application/json' -Body $payload
Invoke-RestMethod "$base/api/v1/game-runs/$($run.id)/report"
# Replaying the same payload/UUID is safe.
Invoke-RestMethod -Method Post "$base/api/v1/game-runs/$($run.id)/explanation" -TimeoutSec 140
```

For a new real run, use a UUID and original client events;
do not edit demonstration data to make it look like a real measurement.
