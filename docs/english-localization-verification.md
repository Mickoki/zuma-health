# English localization verification

Date: November 15, 2026. Baseline: Stitch redesign commit `c475c48`.
Working branch: `codex/english-localization`.

The user requested English throughout the application and project files.
The tracked source tree, documentation, comments, UI text, examples, tests,
model instructions and HTML reports have been translated. Filenames were
already in English/ASCII. Historical design requirements and verification
records were translated without discarding their details.

## Compatibility

API field names, IDs, endpoints, game rules, numeric calculations and SQLite
schema are unchanged. The update does not rename profiles or rewrite existing
user-authored records. Display units and generated fact text are now English.
Both legacy and game-report explanation fingerprints include the current fact
wording, so cached explanations from the old language are treated as stale.
Use the updated server as well as the updated client.

The main app and standalone demo explicitly select the English locale.
An English layout regression test exposed a clipped footer at960×540; slightly
shorter navigation rows and spacing keep the disclaimer and navigation visible.

## Validation

- `python tests/test_english_sources.py`: no Cyrillic in tracked UTF-8 text
  or filenames. API identifiers and mathematical symbols are preserved.
- All seven addon suites pass: rules, module, outbox, recovery, profile ownership,
  layout and redesign input/focus handling.
- All eleven client integration suites pass, with translated assertions and
  unchanged coverage.
- `tests/english_layout.gd`: English locale, navigation and disclaimer remain
  visible at960×540,1280×720,1920×1080.
- `tests/capture_stitch.gd`:48 rendered English states at those three sizes;
  representative home, hard-game and interruption screens were inspected.
- The rendered GUI playtest completed all four hard games at960×540 with
  synthetic mouse events and no errors in the final log.
- All114 named Go tests/subtests pass; vet and formatting pass. New fingerprint regression tests cover
  legacy wording invalidation and current fact wording.
- Real Go/SQLite integration passes for all four completed games, saved survey,
  upload/history/reports and comparable pair-game runs.
- Real local `qwen3:8b` integration passes, including required limitations and
  cached report retrieval. The test now rejects Cyrillic explanation text.
- Exported-scene packaging test and Windows client/server builds pass.
- The English Windows executable starts without Godot or external game assets.
- An independent read-only review found no material runtime, API, persistence
  or test regressions. Ordered format placeholders were checked.

Logs, the temporary translation mapping, test data and screenshots are kept
under ignored `.godot/english/`; they are not distributed as project source.
Private Stitch reference exports and credentials are not included in the build.

## Deliverables and limits

The integrated client and server are packaged as
`builds/windows/Zuma-English-Windows.zip`, with English launch instructions
and existing third-party license notices. The standalone mini-game demo is
also exported by `scripts/build-minigames.ps1` with an English README.

Existing user-entered names can still use any language. Original third-party
license/attribution names are preserved. Old builds and design references
outside the tracked project are not overwritten or retranslated.
The Windows build is unsigned and has not been tested on other team computers.
