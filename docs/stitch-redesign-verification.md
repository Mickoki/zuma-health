# Stitch redesign verification — November 15, 2026

Baseline: final `codex/integrate-minigames`, commit `0e2f491`.
Redesign working branch: `codex/stitch-redesign`.
Mockups: Stitch `projects/1979484546281567767`, project
ZUMA Aerospace Cognitive Telemetry UI. Seven design screens and one HTML
prototype were retrieved. Export links and original previews are stored locally
in ignored `.godot/redesign`; the key exists only in the user's Codex
configuration and the original user attachment.

## Changes

- Translucent dark cards, cyan accent, sidebar navigation, vector icons.
  The survey, Overview, profiles, History, Trends, and Help are preserved.
- Lightweight canvas_item shader: stars, Earth's atmospheric horizon, gentle
  cloud-band movement. No texture downloads or heavy 3D scene.
- Public theme `theme/zuma_theme.tres` and self-contained addon resources.
  System fonts with fallbacks; monospaced timers and counters.
- In the four game scenes: R/Esc, answers 1–4, Speed Math feedback, red pair
  mismatch, amber/green source labels, persistent disclaimer, and a shared
  interruption overlay. Game rules are unchanged.
- Print reports: embedded offline A4 CSS, measures and comparison tables,
  explicit delta units, profile/ID/date/source, validated model facts, and
  a boxed limitation. A single-game report does not invent other games' data.
- Fixed two previously reproduced test-scenario defects: copying addon/assets/theme
  into the temporary export project and waiting for the pair preview using
  the same monotonic clock as the game.

## Checks

- `server`: `go test -count=1 ./...`, `go vet ./...`, gofmt, and Windows CGO0 build.
- Seven addon suites: rules, module, outbox, recovery, profile_ownership,
  layout, redesign. New checks first reproduced missing overlay and keyboard
  support, then input to a hidden scene; they passed after the fixes.
- Eleven client scenarios in `tests/run_client_integration.py`:
  survey/queue/navigation/profiles/history/Overview/charts/Help — PASS.
- Real Go/SQLite: completing all four games, survey, submission, history,
  reports, and comparison of two pairs runs — PASS on a temporary database.
- Real local qwen3:8b: synthetic game with survey, required limitations,
  and cached explanation — PASS.
- Four Hard games completed through GUI mouse events at 960×540;
  final log contained no SCRIPT ERROR/ERROR. Graphical scenarios ran
  sequentially: another window can legitimately cause focus_lost.
- `tests/capture_stitch.gd`: 48 actual interface screenshots at 960×540,
  1280×720, 1920×1080; checked button bounds on Hard game boards.
  Screenshots reviewed; overlapping disclaimers in the compact window fixed.
- Addon copied into a separate minimal project; rules/module/layout/redesign
  passed without resources from the main application.
- Dynamically loaded scene export test — PASS. Windows client export and
  headless EXE smoke test — PASS. HTML report reviewed in a browser.
- Independent review found hidden keyboard input, the demo shader covered by
  the old background, and an ambiguous accuracy-change unit. All fixed;
  accuracy delta is labeled in percentage points, null remains a dash.

Check commands are in README and the addon README. Logs and screenshots:
`.godot/redesign/` (excluded from Git). Test data is synthetic.

## Limitations and decisions

The final version's existing architecture is preserved: a profile and saved
survey are required before playing in the main application; the standalone
addon demo works without a profile. The old list of 50 screenshots describes
states rather than 50 independent copies of game scenes. Styling was extended
to the final client's new pages.

Decorative pulse, overall cognitive-load percentage, fictional hardware
measures, and incorrect timings from the mockups were not added. There is no
diagnosis/overall health score. API and SQLite contracts were unchanged.

The Windows build is not certificate-signed. Other computers and physical
mobile devices were not tested. Installed system fonts may differ.
MCP was added to the user's config.toml; Stitch tools will become available
normally after restarting Codex. In the current session, mockups were retrieved
directly through the same MCP protocol.
