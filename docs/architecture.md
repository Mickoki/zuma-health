# Architecture

Zuma combines a Godot desktop client, a local Go HTTP API, and SQLite.
Ollama runs Qwen3 8B as a separate optional service.

## Data flow

1. Select a server profile and save a wellbeing survey.
2. Play a game. Each attempt includes a snapshot of the saved survey.
3. The client stores completed attempts in an outbox and uploads them.
4. Go validates the run, replays supported events, and stores the result.
5. Reports show calculated measures and comparable earlier attempts.
   Optional model explanations use server-provided facts.

Calculations remain in Go. Legacy reaction and memory sessions use a separate
protocol. Games are experimental measures, not diagnoses.

## Boundaries

`addons/zuma_minigames/` owns reusable gameplay and shared visual resources.
`scripts/` and `scenes/` provide application navigation and integration.
`server/` owns validation, persistence, reporting, and model communication.
`tests/` verifies these boundaries with synthetic data.

See [server setup](../server/README.md) for environment variables, database
location, and backups; [OpenAPI](../server/docs/openapi.yaml) for the API;
and [game protocol](../server/docs/minigames.md) for run validation.
Godot keeps drafts and its outbox in the application user directory.
Databases and client data must not be bundled in release archives.
