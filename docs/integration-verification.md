# Zuma integration verification — November 14, 2026

Original minigames branch: `feat/minigames-module`, commit `4a68aaa`.
The main application was checked against snapshot `snapshot/demo-app-2026-11-14`,
commit `4accabf`; the result was published to the team's repository branch
`codex/integrate-minigames`.

## Verified

- Server: `go test ./...` passed, including survey validation in the game
  payload, immutable data on retries, and conflict errors. A separate test
  with mock Ollama checks selection of a survey fact, the required limitation
  about the unknown completion time, and rejection of nonexistent facts for
  old runs without a survey.
- Client: `python tests/run_client_integration.py <Godot console>` passed,
  including Overview, chart, and game history page checks with a test API.
- `python tests/run_real_server_integration.py <Godot console> <server exe>`
  passed using a separate temporary SQLite database: four aborted test runs
  with survey snapshots were sent and their reports retrieved. A separate
  check confirms that an unavailable queue destination does not block a
  working destination. Another part of the same test completes all four
  games through game-button signals in headless Godot, submits five runs
  with a survey, and checks reports and comparison of two comparable Find
  the Pair runs. This does not test physical mouse actions or the finished exe.
- Godot rendered the menu and all four game scenes at 960×540; game boards
  and main buttons were visible. This verifies rendering, not four complete runs.
- The Windows x86-64 client `Zuma-integrated.exe` was exported. In its real
  window, using a separate test database, a profile and survey were created,
  Speed Math was completed, and sending, history, Overview, and a survey chart
  point were checked. To test errors, the queue contained records with an
  unavailable address; after the fix, the record for the working server was
  sent and unsent records remained. The entered values and profile were fictional.

The server ran from `builds/windows/zuma-server.exe`; the model was deliberately
unavailable. `tests/run_model_integration.py` was prepared to recheck installed
Qwen using a synthetic game and temporary database; the scenario itself was
checked with a local test substitute for Ollama. Ollama is unavailable on the
current computer, so the new survey integration with the real model has not
been confirmed here.
Visually completing the other three games and testing the finished package
on the presentation computer remain useful final checks. This record does
not establish medical validity or competition eligibility.
