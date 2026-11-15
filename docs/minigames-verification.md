# Minigames module verification — 2026-11-14

Four independent games in `addons/zuma_minigames/` and a Go API for individual
runs were implemented. Working branch: `feat/minigames-module`; nothing was
published or merged. The main application menu was not connected to the module.

## Confirmed scenarios

| Requirement | Check and result |
| --- | --- |
| Four games, random layouts, three difficulties | Godot `test_rules.gd`: PASS; 12 Godot logs accepted by independent Go replay |
| Instructions, start, restart, exit, results | Four complete GUI runs on Hard at 960×540: PASS |
| Addon portability | Six headless suites in the main and a separate minimal project: PASS |
| Focus and module removal | `test_module.gd`: a single aborted result, including host_removed |
| Storage and migration | Go: migrating populated schema 1→2 preserves old records; repeated UUID and concurrent writes checked |
| Server calculations and history | All four GUI results submitted to the API, saved, and retrieved through history and JSON/HTML reports |
| Comparison | Isolation by game, configuration, difficulty, source, and outcome; aborted runs excluded; chimp losses compared |
| Offline operation and restart | A separate offline process saved 12 records; a new online process delivered exactly 12 |
| Lost acknowledgment | Retrying an already-saved UUID did not create a 13th record |
| Delivery errors | 409/422 keep the record in the queue; an unavailable server stops the upload batch |
| Result ownership | `test_profile_ownership.gd`: failed profile switching rolls back; unbound games do not inherit an old binding |
| Corrupted files | `test_recovery.gd`: invalid nested routes/receipts/bindings handled without losing valid records |
| Local model | Real qwen3:8b through Ollama: a new Speed Math report became ready and was cached; model absence does not block games/reports |
| API contract | Swagger Parser and AJV2020: OpenAPI 3.1, four examples, four real run/report pairs, history, and Qwen response — PASS |
| Standalone Windows build | Release x86_64 with embedded PCK: headless launch exit 0; native window, menu, instructions, and Fifteen Puzzle board checked |

## Commands and evidence

Go (from `server/`):

```powershell
$env:ZUMA_GODOT_FIXTURES = 'C:\Documents\Zuma\zuma-health\.superpowers\sdd\2026-11-14-minigames\generated'
go test -count=1 -json ./...
go vet ./...
gofmt -l .
$env:CGO_ENABLED = '0'
go build -o zuma.exe ./cmd/zuma
```

Go result: 108 named tests/subtests PASS, 0 FAIL. Packages cmd/zuma and
internal/testutil have no test files of their own. Vet and the CGO0 build
exited with code 0; gofmt listed no files.

Godot 4.7.2: `--headless --path <project> --script
res://addons/zuma_minigames/tests/<suite>.gd`. Suites: test_rules, test_module,
test_outbox, test_recovery, test_profile_ownership, test_layout.
GUI testing used playtest_ui.gd and test_upload_ui.gd.

Local logs, 12 original fixtures, GUI screenshots, and server-evidence.json
are saved in `.superpowers/sdd/2026-11-14-minigames/` (excluded from Git).
The four games were played again for the user to record;
the agent did not create a video file.

Independent final review found six issues: incorrect profile switching,
inheriting an old binding, corrupted routes/receipts, late Speed Math
completion, null in integer arrays, and missing synthetic-run labels.
All were fixed, and regression checks were added.

## Startup and limitations

The working server was updated and left running at `http://127.0.0.1:8080`;
readyz=ready, qwen3:8b available. Before updating the stopped server, a data
backup was saved to
`.superpowers/sdd/2026-11-14-minigames/working-db-backup-20261114-183427`.

The Windows package is built with `scripts/build-minigames.ps1`. Finished EXE
and ZIP files are in `builds/minigames-windows/` and excluded from Git.
This is an unsigned Windows 64-bit demonstration build; the team's other
devices were not tested. Offline games need neither Godot nor the server.
The build's local data is separated from the editor by `%APPDATA%/ZumaMinigames`.

Measures describe task performance and are neither a diagnosis nor an overall
health score. The API is intended for local use; a remote authenticated server
and connection to the main menu remain outside this task's scope.
