# Zuma

Desktop prototype for the NASA Space Apps health monitoring challenge.
Godot provides four cognitive minigames; a local Go API stores results,
calculates measures, and generates reports. Optional Qwen3 8B explanations
run through Ollama. Results are experimental, not medical diagnoses.

## Run from source

Requires Godot 4 (tested with 4.7) and Go 1.26+.

```powershell
cd server
go run ./cmd/zuma
```

Open `project.godot` in Godot and run with F5. The API defaults to
`http://127.0.0.1:8080`; `/` does not serve the desktop interface.
Create a profile, complete and save the survey, then play Fifteen Puzzle,
Find the Pair, Speed Math, or Remember the Numbers. Results enter a local
queue before upload. Failed uploads can be retried. Update the saved survey
when wellbeing changes. History, Trends, and reports expose saved results.
Legacy reaction and memory sessions remain separate from minigame runs.

## Windows package

```powershell
./scripts/build-windows.ps1 -Godot 'C:\path\to\godot.exe'
```

Output: `dist/windows/` and `dist/Zuma-Windows.zip`. Start `zuma-server.exe`
and then `Zuma.exe`. Ollama and model weights are installed separately.
For the standalone game demo, use `scripts/build-minigames.ps1`.

## Project layout

| Directory | Contents |
| --- | --- |
| `addons/zuma_minigames/` | Reusable games, rules, shared theme, icons, and tests |
| `scripts/`, `scenes/` | Desktop application and build scripts |
| `server/` | Go API, SQLite, reports, and model integration |
| `tests/` | Client and integration verification |
| `docs/` | Architecture, verification, integration, and submission |
| `third_party/` | Dependency licenses and notices |

`dist/`, `builds/`, and `.godot/` contain ignored generated files. Keep user
SQLite databases and client data out of release packages. Stop the server
and back up its database before updates: old binaries may not support a
migrated database. Local data is not encrypted. Watch integration is excluded.

## Documentation

- [Architecture](docs/architecture.md) and [verification](docs/testing.md)
- [Server setup and storage](server/README.md)
- [API](server/docs/openapi.yaml) and [game protocol](server/docs/minigames.md)
- [Reusable module](addons/zuma_minigames/README.md)
- [Legacy game integration](docs/game-integration.md)
- [Space Apps submission](docs/space-apps-submission-en.md)
- [Third-party notices](third_party/README.md) and [license](LICENSE)
