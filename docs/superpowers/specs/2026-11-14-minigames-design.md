# Zuma: four-minigame module and backend extension

Date: 2026-11-14. Status: approved by the user, including randomness and +50% parameters; independent implementation authorized without intermediate approvals.

## Goal and decisions

Create four minigames and storage for their independent runs, history,
result comparisons, reports, and Qwen3 8B explanations. The user selected
delivery as one portable folder, `addons/zuma_minigames/`, with a separate
demonstration scene. Godot 4.7.2 / GDScript, the existing Go backend,
SQLite, and local Ollama are retained.

The rules and concrete values below were proposed by the implementer based
on the goal; they are subject to approval of this document. The main application
menu is not automatically connected to the module. Existing user changes to
project.godot and the example's UID file are neither overwritten nor included
in this work's commits. Development takes place in the current folder on a new
feat/minigames-module branch.

Result workflow: instructions → start task → play → local result and save →
send when the server is available → history and report. Neither the model nor
the server is needed for gameplay itself. The work excludes medical validation,
diagnoses, an overall health score, watches, authentication, and GitHub publication.

## Approaches

1. **Selected:** addon with its own scenes, resources, GDScript API, and demo.tscn
   inside the existing project. Copy one folder; no Autoload or main-menu
   dependency. Launch the demonstration with F6 or --scene.
2. Separate Godot project and exportable library: convenient independent
   opening, but transfer and a shared resource source also require maintenance.

The addon is not an EditorPlugin: it does not need enabling in editor settings.

## Games and v1 rules

Each game has a stable game_id and rules_version=1. Initial layouts, tasks,
accepted actions, and timestamps are recorded; the backend replays the logic
and independently calculates measures. Go and Godot randomness need not be
synchronized: submitted initial data is validated, rather than the RNG algorithm.
Difficulty parameters enter the comparability key; the seed/random layout does not.

### Randomness and difficulty increase

At the user's request, every new start receives a fresh random layout or task
set. Use a local RandomNumberGenerator with a new seed without changing the
host application's global generator. Fifteen Puzzle is shuffled using random
legal moves; Find the Pair uses a random deck permutation; Speed Math samples
distinct problems and shuffles options; chimp uses new number positions in
every round, including retries after mistakes. The immediately preceding layout
for the same game/difficulty in the current module launch is not repeated:
detect a match and generate a different variant. A new seed is also created
after restarting the application, but retaining a complete layout archive and
prohibiting repetition forever is unnecessary.

The user requested a 50% difficulty increase. Selected load parameters below
are increased: Fifteen Puzzle shuffle count, number of pairs, operand upper
bounds, and number of cells to remember. Preview times, time limits, number
of arithmetic problems, and allowed mistakes are not tightened further.
Fractional cell counts round up. This changes task parameters; it does not
claim a scientifically measured cognitive difficulty increase of exactly 50%.

### Fifteen Puzzle — fifteen

A 4×4 board with numbers 1–15 and empty cell 0. Goal: 1–15 in row order,
empty cell at bottom right. Only an orthogonally adjacent tile can move.
Invalid clicks are not moves and are not added to the accepted-action log.

Easy/Normal/Hard: 30/90/180 shuffle moves from the solved state
(original 20/60/120 increased by 50%).
Immediate reversal during shuffling is prohibited; the final board must not
be solved. Save the shuffle sequence and initial_board. The server checks
shuffle legality, length, matching layout, permutation of 0–15, solvability,
and every player move. Shuffle count is a task parameter, not a claim about
the optimal distance to a solution.

Measures: accepted moves, duration_ms until solution/interruption, solved.
An unsolved board cannot be marked completed; moves cannot continue after
solution. There is no loss timer: time is displayed and measured.

### Find the Pair — pairs

Easy/Normal/Hard: 9/12/18 pairs (50% increase from 6/8/12), preview
5000/4000/3000 ms. The maximum 36 cards must fit a 960×540 viewport.
Each symbol occurs exactly twice. All cards start face up with input locked;
after the preview they turn face down. The player flips two distinct unmatched
cards. A match leaves the pair face up. A mismatch is shown for 700 ms before
both cards are hidden; input is locked during the delay. Clicking the same
card again or an already-matched card is ignored.

Record initial_cards and the sequence of accepted flip actions with indices
and times. The server validates pairs, index bounds, action order, preview
completion, post-error delay, and matched/open cards. In completed runs, all
pairs are found; an unfinished one-card selection is allowed only for aborted
runs. Measures: matched pairs, attempts (two flips), errors (mismatched attempts),
pair accuracy, play time after preview, and total duration. With zero attempts,
accuracy is null. Symbols and visuals are created within the module.

### Speed Math — math

Generate 20 distinct random tasks before starting; overall limit 60000 ms.
Each problem allows at most 8000/6000/4000 ms for Easy/Normal/Hard, bounded
by remaining overall time. Answer or click “Skip”; timeout also counts as a
skip. The game ends after 20 tasks or the overall limit. This is normal
completed status even without correct answers. Future tasks not yet shown
are not counted as skipped.

Each problem has four unique integer answer options with exactly one correct
answer. Operations use enum add/sub/mul/div rather than a string for eval.

- easy: 10 additions and 10 subtractions, operands 0–30; subtraction has a nonnegative result.
- normal: 7 additions, 7 subtractions (0–75, nonnegative result), and 6 multiplications with operands 0–18.
- hard: 5 tasks per operation; addition/subtraction 0–150, multiplication 2–30; exact division: divisor 2–18, quotient 2–30.
- Task and option order is shuffled; option values range from -1000 to 1000.

Operand upper bounds are increased by 50% from the initial proposal.
There is no shared static list of 20 tasks: the generator samples from the
complete finite space of allowed expressions. Swapping addition/multiplication
operands does not create a new problem: 2+3 and 3+2 share a key. Subtraction
includes only a>=b; division is exact under the rules above. Keys do not repeat
within a run. Answer options do not count toward expression totals and are
generated separately.

| Difficulty | Addition | Subtraction | Multiplication | Division | Total distinct expressions |
| --- | ---: | ---: | ---: | ---: | ---: |
| easy | 496 | 496 | 0 | 0 | 992 |
| normal | 2926 | 2926 | 190 | 0 | 6042 |
| hard | 11476 | 11476 | 435 | 493 | 23880 |

For range 0…M, the number of additions with a<=b and subtractions with a>=b
is (M+1)(M+2)/2 per operation. Hard multiplication: 29*30/2=435;
hard division: 17 possible divisors * 29 quotients = 493.
Each run still takes 20 tasks with the specified operation quotas.

The log contains each problem's display and answer/skip/timeout with times.
At the deadline boundary, timeout takes priority: only answers before the
deadline are accepted. The server checks arithmetic, operation distribution,
exactly one correct option, sequence, shown tasks, and deadlines. Measures:
shown, correct, incorrect, skipped with reasons, answered, accuracy among
answered (null if zero), mean/median accepted-answer time, and correct answers
per minute of active play (null for zero duration).
Frame delay may record a timeout event after the deadline; this does not allow
a late answer. No new tasks are shown after the overall deadline; finish with
time_limit is possible only at duration_ms >= 60000.

### Remember the Numbers — chimp

An original implementation of the mechanics in the user's link, without
copying the site's graphics, text, or code. Grid: 8×5. Numbers 1…N occupy
distinct random cells; other cells are not selection buttons.

Easy: start 5, target 12 numbers, maximum 4 mistakes; Normal: start 6, target 18,
maximum 3 mistakes; Hard: start 9, target 24, maximum 2 mistakes.
Starting and target sizes are increased by 50%; original 3*1.5=4.5 rounds
up to 5. All sizes fit the 40-cell grid.
Numbers are visible at the start of a round. After correctly selecting 1,
numbers on remaining cells are hidden; select 2…N from memory. Selected cells
are disabled. A wrong choice immediately ends the round with an error. After
an error, show a new layout with the same N; after success, increment N by 1.
A successful round at target N ends the game as completed. Reaching the
mistake limit ends it as failed.

Record every round display (positions in number order), cell selections, and
times. The server checks distinct positions within the grid, starting size,
growth after success, repeated size after error, selection order, mistake
limit, and terminal state. The player confirms the next round with a button;
waiting between rounds counts toward total duration but not memorization or
cell-selection time. Measures: successful/erroneous rounds, maximum successfully
completed size (null without successes), errors, viewing time until selecting 1,
and round execution time after selecting 1. Memorization time is not interpreted
as a diagnosis.

## Shared log, time, and completion

Shared envelope: client_run_id (UUID), game_id, rules_version, difficulty,
config, source (observed/synthetic), performed_at, status, finish_reason,
duration_ms, initial, events. Layouts/tasks are game-specific; events have
kind and t_ms plus documented action fields. Empty/unknown fields and
inconsistent types are rejected according to each game's schema.

performed_at is the UTC RFC3339 task start; duration_ms/t_ms are integer
milliseconds from Godot's monotonic clock, without using the system clock
for durations. t_ms is nondecreasing and within [0,duration_ms]; a final
finish event is required and equals duration_ms. No events follow it.
Input calendar timestamp rules and server IDs remain as in API v1.
Later delivery does not change performed_at.

status: completed/failed/aborted. Validate finish_reason by game:
solved (fifteen/pairs), questions_done/time_limit (math), target_reached/
mistake_limit (chimp), user_exit/focus_lost/host_removed/recording_limit (aborted).
An arbitrary status cannot contradict the replayed state.

“Back”, “Restart”, and leaving an active scene finish and save the current
attempt as aborted, then create a new UUID if needed. During instructions,
the attempt has not started and has no result. Losing focus interrupts a
started run with focus_lost: hidden waiting and repeat viewing must not distort
measurements. Resuming an interrupted game is unsupported in v1.
After normal completion, a second completion signal is prohibited.

Technical limits for new runs: 1 MiB JSON, at most 10000 events, duration_ms
at most 24 hours. As recording approaches a limit, the module ends the attempt
with recording_limit before overflowing. These limits are not a player assessment.
Old endpoints retain their 256 KiB limit.

The server checks internal log consistency; it cannot prove the client's clock
is accurate or that another process did not act for the player. Reports describe
local client data, not anti-cheat guarantees or clinically validated measurements.

## Godot module contract

The addons/zuma_minigames folder contains a host component, four game scenes,
separate rules classes, theme/resources, transport/outbox, demo.tscn,
integration instructions, and test scripts. All resource references stay
within the addon's namespace; there are no dependencies on external scenes,
Autoloads, InputMap, or the main application's node names. Shared class_name
values have the ZumaMinigames prefix, or local preload is used to avoid conflicts
with the host project.

Public operations: configure(options), start_game(game_id,difficulty),
cancel_game(), retry_pending(). Signals: run_finished(payload),
delivery_changed(client_run_id,state,message), module_exit_requested().
Exact GDScript types and Error codes are documented in README/API examples.
Results are formed and signaled independently of HTTP; write/delivery errors
are also visible and are not presented as successful persistence.

Each scene shows instructions, difficulty settings, time/progress, available
controls, results, restart, and exit. Buttons support keyboard focus and mouse;
minimum viewport 960×540, main viewport 1280×720. The demonstration includes
selection of four games/difficulty, a profile, and queue state. Exact visual
style and layout are left to the implementer; text is in Russian.

The demo starts separately via F6 or CLI --scene and does not change the root
main_scene. Portability must be tested: copy only the addon to a temporary
minimal Godot project where the host receives result signals.

## Reliable offline queue

Default: user://zuma_minigames/; configure can override the directory.
One immutable JSON record per client_run_id: owner_key, profile_id (if known),
destination address, and payload. First write to a temporary file in the same
directory, check errors, flush/close, then rename. Incomplete or corrupted
records are preserved for recovery/diagnostics, never silently deleted.
Enqueuing the same UUID again does not create a new attempt.

Sending requires an existing server profile_id. An offline launch uses a
separate owner_key; until the host/demo explicitly binds it to profile_id,
results remain unassigned. Switching profiles does not reassign old records.
The demo allows creation/selection of a server profile and explicit binding
of a local owner; the main host passes this binding through configure.

Sending is sequential with one worker only. An automatic attempt follows
completion, plus a “Retry sending” button; errors do not cause an endless
rapid loop. Network errors, 409, 422, and other responses are visible; the
payload remains on disk. Only 200/201 with confirmed client_run_id and server
run_id count as delivery; the record is marked/moved to sent with a receipt.
If the response is lost or the application restarts before recording the
receipt, retry uses the same UUID and the server returns the existing result.
Receipt-write failure does not lose the payload. Batch results are not sent
to a single profile without checking their bindings.
Immutability applies to the game payload. The owner_key binding to profile_id
and server is stored separately; the selected address and profile are fixed
before the first send of a particular UUID. A failed request does not allow
automatic reassignment to another profile/server.

## Go API, SQLite, and compatibility

Existing /api/v1/profiles and /sessions and their schemas/responses are preserved.
New endpoints use existing profiles:

| Method and path | Result |
| --- | --- |
| POST /api/v1/profiles/{id}/game-runs | 201 creation; 200 identical retry; 409 changed payload with the same UUID |
| GET /api/v1/profiles/{id}/game-runs | History, limit/offset, optional game_id |
| GET /api/v1/game-runs/{id} | Raw result and server metadata |
| GET /api/v1/game-runs/{id}/report | Calculated measures, comparison, limitations, current explanation |
| GET /api/v1/game-runs/{id}/report.html | Escaped HTML for viewing/printing |
| POST /api/v1/game-runs/{id}/explanation | ready/unavailable/invalid, as in the existing API |

Pagination/error/loopback/no-auth constraints match the current API.
The initial/config/events schemas are a discriminated union by game_id;
unknown fields/versions/difficulties are rejected. Valid zero values differ
from missing/null values. Calculations and validation precede atomic saving.
Canonicalizing equivalent payloads and uniqueness of (profile_id,client_run_id)
ensure concurrent retries without duplicates. A UUID belongs to one game_id.

SQLite version=2: new game_runs and game_run_explanations with profile, time,
and comparability indexes. Migration 1→2 is transactional and does not change
existing data. Reports are recalculated from the raw log, calculation_version=v1.
Sensitive data and test databases stay out of Git. Rollback requires a backup;
the old server correctly refuses to open the new schema.

## Comparison and report

Every attempt appears in history, including aborted/failed with a reason.
Baseline is the nearest strictly earlier comparable run for the same profile,
game, rules version, canonical difficulty configuration, and source.
For fifteen/pairs/math, completed runs are compared. For chimp, both winning
and reaching the mistake limit are normal outcomes: completed/target_reached
is compared with the same outcome, failed/mistake_limit with failed/mistake_limit.
Thus a typical chimp loss also receives trends for maximum successfully
completed size and other available measures. Aborted runs do not participate
in baseline selection or comparison; their own measures and limitations remain visible.

Versions and configurations are shown explicitly; the same difficulty name
with different settings does not imply comparability. Without a baseline,
return null. Time measures are in ms, accuracy differences in percentage points.
Move/error/score differences use their original units. Do not create an overall
measure across different games. Synthetic source is prominent on screen and
in the report.

Qwen receives only server facts for the new game, comparison, and limitations,
without the profile name. Old Explain remains compatible; the shared fact_ids
selection mechanism, free-text prohibition, timeout, and single generation
slot apply to both report types. Go adds mandatory limitations. The fingerprint
includes rules, raw run, calculations, and selected baseline; stale explanations
are not published after backfill. Model failure neither changes data nor
erases an already-ready current explanation.

## Verification and completion criteria

1. Godot headless: every game's logic, boundaries, completion/restart, prevention
   of duplicate completion, host signals, and new layouts on new starts.
   Generators are also tested with a fixed seed without affecting normal
   randomness; the math pool and task uniqueness are checked independently
   of the generator. Fifteen Puzzle: solvability and legal moves; pairs:
   preview/lock, matches, and errors; math: exactly one correct answer and
   deadlines; chimp: hiding, order, round growth, and mistake limit.
2. Godot with rendering: complete all four scenes through the UI, checking
   instructions, controls, cards/numbers, results, and 960×540 layout. Screenshots
   and reproducible scenarios are not replaced by successful parsing alone.
3. Test from a temporary minimal project without the root main-menu/Autoload.
4. Offline/outbox: no server, no profile_id, restart and queue recovery, lost
   response, retry, disk failure/corrupted record, profile switching, and
   server-rejected result. Data must not be lost silently.
5. Go: replay valid/forged logs for every game, zero/required fields, deadlines,
   configurations, idempotency/concurrency, migration from an old database
   with a profile/session/explanation, history, and both report formats.
6. Compatibility: the entire existing Go test suite remains green. The new
   body limit does not change old endpoints. HTML is escaped.
7. Complete Godot → API → SQLite → history → report workflow for each game,
   with Ollama absent, then at least one real new-game explanation from
   installed qwen3:8b. Mock tests check allowed-fact selection for every game,
   timeout, cancellation, and contention between old/new endpoints.
8. gofmt, go vet, go test, Windows build without a C compiler; Godot import
   and headless tests without errors. Update OpenAPI, README, examples, and
   instructions for copying the addon, launching the demo, handling signals,
   and backups.
9. Independent review and final evidence document. Do not consider the task
   complete until every game has been tested in the installed Godot.

## Implementer decisions

Exact internal file/type and event-field names, UI text/layout, card visuals,
SQL structure within the described model, generator and test-input implementation,
OS file-error handling, and the receipt's technical format. These decisions
must preserve this document's rules and verifiability.
