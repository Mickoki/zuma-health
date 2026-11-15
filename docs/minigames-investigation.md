# Four minigames: starting conditions

Date: 2026-11-14. These are investigation findings, not an approved specification.

## Checked in the working directory

- Current branch: `feat/go-backend`, tracking the same-named origin branch.
- User changes/editor metadata are present: `project.godot` is marked modified,
  and `server/examples/client.gd.uid` is untracked. The text diff for
  project.godot is empty; these files were not changed during investigation.
- The main project has a startup menu but no working minigames.
- Installed engine:
  `C:\Games\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`.
- `--headless --version`: `4.7.2.stable.steam.ed1daf0bf`.
- Baseline `go test ./...` from server/: PASS for all existing packages.

## Confirmed user requirements

Required games: a 4×4 Fifteen Puzzle, Find the Pair with all cards initially
shown, timed multiple-choice Speed Math, and Remember the Numbers with number
positions hidden after the first correct click. The module must integrate with
the main application, work without a server, store unsent results, and retry
them safely. Server-side history, comparisons, JSON/HTML reports, and Qwen3 8B
explanations through Ollama are required. The old API is preserved.

## Server extensions needed

- SessionInput currently requires survey, reaction, and memory.
  The four new games need a separate run contract without those fields.
- SQLite schema version=1; new tables and a migration must preserve existing
  profiles, sessions, and explanations.
- domain.Report and domain.BuildFacts describe the legacy reaction/memory tasks.
- model.Client.Explain accepts domain.Report and calls BuildFacts itself.
  The new games need a shared validated-fact input, with the existing Explain
  contract retained as a compatibility adapter.
- The current overall JSON body limit is 256 KiB. Event and duration limits
  for the new games must fit within the documented request size.
- Results from different games or different rules/difficulties cannot be
  compared directly; the comparability key must include game_id, rules_version,
  and configuration.

## Module delivery options

1. An `addons/zuma_minigames/` folder inside the current Godot project with its
   own scenes, logic, resources, API, and demo.tscn for standalone F6/CLI launch.
   No main menu/Autoload is required. Integration copies one folder; the host
   application instantiates the scene and subscribes to signals.
2. A separate Godot project with its own project.godot and an exportable module
   folder. The demo opens completely independently, but a single resource
   source and correct transfer into the host project must also be maintained.

The user selected option 1: `addons/zuma_minigames/`.
Card counts, preview times, arithmetic settings, round progression, and the
error limit are proposed in the draft specification; approval is pending.

The user additionally requested random layouts and a 50% difficulty increase.
The draft specification now includes new parameters and exact arithmetic
space sizes: easy 992, normal 6042, hard 23880 expressions;
20 distinct problems per run. The module and new APIs have not yet been implemented.

## Additional checks

- The installed Godot supports CLI `--scene`, `--headless`, `--script`,
  `--check-only`, and `--quit-after`: demo launch and engine logic checks are available.
- Existing `res://server/examples/client.gd` was checked directly in Godot
  4.7.2 with `--headless --path <repo> --script
  res://server/examples/client.gd --check-only`: exit 0, no type/syntax errors.
  This checks the old API example rather than completing future minigames.
- Time documentation recommends monotonic get_ticks_msec/get_ticks_usec for
  durations; the system clock is suitable only for calendar timestamps.
- FileAccess supports persistent storage in user://, flush, and close;
  stopping via F8 can interrupt writing. The queue needs a temporary file,
  write-result verification, and recovery after an incomplete operation.
- DirAccess provides file operations with error codes; write and rename errors
  must not be treated as successful persistence.

Sources:

- https://docs.godotengine.org/en/stable/classes/class_time.html
- https://docs.godotengine.org/en/stable/classes/class_fileaccess.html
- https://docs.godotengine.org/en/stable/classes/class_diraccess.html

## Implementation outcome

The module and server extension are implemented. Verification results and
limitations: [minigames-verification.md](minigames-verification.md). The original
investigation above is retained as historical context.
