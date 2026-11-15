# Zuma — team plan

A local game-based prototype for observing astronauts' wellbeing and cognitive
task performance. The current prototype saves a survey and attaches a snapshot
to runs of four games; each run has history and reports. Model explanations
are optional. Watches are excluded. Results are not a diagnosis.

## Architecture and responsibilities

- Godot / GDScript: the application shell, profiles, survey draft, history, reports, charts, and full-session queue are ready; four independent minigames are connected to the profile and a separate run queue.
- A single Go server in server/: API, data validation, calculations, and reports.
- SQLite: profiles, immutable sessions, and validated explanations.
- Qwen3 8B through local Ollama: selection and ordering of validated facts.
- Once components are installed, the workflow operates without internet access; the model is optional.

Roles: UI/UX, Godot interface, minigames, Go backend and model,
research and testing, coordination and presentation.

## Connecting the client

1. Attach a snapshot of the saved survey to each new run. A combined reaction and memory session requires different game scenes and a different protocol.
2. Use [OpenAPI](server/docs/openapi.yaml) and [GDScript](server/examples/client.gd).
3. Games use their own queue with UUID/payload and API: [contract](server/docs/minigames.md).
4. Clearly show history, source, missing baseline, and explanation status.
5. Check the Windows Godot build with the local server and finished games on the demonstration computer. Building, visually completing Speed Math, and rendering all four games were checked in an isolated test environment; see [verification results](docs/integration-verification.md) for details and limits.

To demonstrate legacy reports, create a separate profile with fictional checks
as described in README. Its data is labeled as demonstration data.

Backend documents: [specification](docs/superpowers/specs/2026-11-14-backend-design.md),
[implementation plan](docs/superpowers/plans/2026-11-14-backend.md).

## Sources

- https://www.spaceappschallenge.org/2026/challenges/health-monitoring-software/
- https://www.nasa.gov/hrp/risks/
- https://www.nasa.gov/hrp/ongoing-hrp-research/
- https://www.spaceappschallenge.org/resources/project-submission-guide/

These sources provide context but do not establish the medical validity of our tasks.
Real records, builds, and model weights are not stored in Git.
