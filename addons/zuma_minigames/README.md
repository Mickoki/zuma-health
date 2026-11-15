# Zuma Minigames

Portable module for **Godot 4.7.2 Standard / GDScript / Compatibility**.
Four games, instructions, difficulty levels, results, an offline queue, and
delivery to the Go API. The application's main menu is unchanged.

The module includes its own SVG icons, theme, and lightweight orbital-background
shader. Copying them with the addon folder preserves standalone operation.
The main application shares the theme at `addons/zuma_minigames/theme.tres`.
Timers use a system monospaced font (JetBrains Mono, Consolas, or DejaVu Sans Mono);
startup requires neither internet access nor font downloads.
R restarts the game, Esc goes back, and 1–4 selects an answer in Speed Math.
Losing focus opens an overlay; hidden scenes do not accept shortcuts.

## Open the demo

Open `demo.tscn` from this folder in Godot and press F6, or use PowerShell:

```powershell
& 'C:\Games\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --path 'C:\Documents\Zuma\zuma-health' --scene res://addons/zuma_minigames/demo.tscn
```

In the demo, select a game/difficulty, create or select a server profile,
explicitly bind previous local results, and retry sending. Games are available
without a server; without profile_id, results remain unassigned. New games
started with “No server profile” do not inherit a previously bound profile.

Losing window focus interrupts a started attempt. Before recording the screen,
configure the recorder, then return to the game window and start. The interrupted
result is saved; “Restart” creates a new attempt with a new UUID and random layout.

## Connect to another application

Copy the **entire** `addons/zuma_minigames` folder to the same location in the
host project. No Autoload, EditorPlugin, extra InputMap actions, or main
application scenes are required. The module uses its own resources and local
preload; there are no global class_name declarations. Minimum module area: 960×540.

```gdscript
const Minigames = preload("res://addons/zuma_minigames/module.tscn")
var games

func _ready() -> void:
	games = Minigames.instantiate()
	add_child(games)
	games.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	games.run_finished.connect(_on_result)
	games.delivery_changed.connect(_on_delivery)
	games.module_exit_requested.connect(func(): games.hide())
	var profile_id: String = "<existing 32-character server profile ID>"
	var error: Error = games.configure({
		"base_url": "http://127.0.0.1:8080",
		"profile_id": profile_id,
		"owner_key": "profile:" + profile_id,
		"storage_dir": "user://zuma_minigames",
		"source": "observed",
		"auto_upload": true
	})
	if error != OK:
		push_warning("Delivery configuration error: %d" % error)
	games.start_game("pairs", "normal")

func _on_result(payload: Dictionary) -> void:
	# Called once after completion/abort, even without HTTP.
	print(payload.client_run_id, " ", payload.status)

func _on_delivery(client_run_id: String, state: String, message: String) -> void:
	print(client_run_id, " ", state, " ", message)
```

Public methods:

- `configure(options: Dictionary) -> Error`: before an active game/upload;
  ERR_BUSY if configuration changes are attempted during either operation,
  ERR_INVALID_PARAMETER for invalid parameters. Disk errors are returned
  explicitly, but gameplay remains available and unsaved results stay in memory.
  Optional `survey` is a saved survey with four numeric fields:
  `sleep_hours`, `fatigue`, `stress`, `mood`; its snapshot is captured at task
  start and included in the immutable payload. An empty dictionary preserves
  standalone-module compatibility with previous runs.
- `start_game(game_id: String, difficulty: String = "easy") -> Error`:
  opens instructions; gameplay begins with the “Start” button.
- `cancel_game()`: saves the active attempt as aborted without finishing it twice.
- `retry_pending()`: one sequential delivery attempt for accumulated records.
- `pending_count() -> int`: number of pending/not-yet-written results.
- `bind_owner(owner_key: String, profile_id: String) -> Error`: explicitly binds
  a previously local owner to a profile. The binding is immutable; another
  profile requires another owner_key. The address comes from configure.

Signals:

- `run_finished(payload: Dictionary)` — a semantically immutable run log.
- `delivery_changed(client_run_id: String, state: String, message: String)` —
  pending/sending/sent/unassigned/storage_error/storage_warning. Message is
  human-readable text rather than a machine-parsing format. The server receipt
  with its ID is available in the sent archive; the host application can also
  send payloads and obtain server IDs itself by setting auto_upload=false.
- `module_exit_requested()` — the player clicked “Back”; the host decides which
  screen to show.

For offline startup without a profile, pass an empty profile_id and your own
stable owner_key. The host must persist this key across restarts and separate
local players. After binding, create a new unassigned owner_key for future
guests; an immutable key does not represent a new person.

## Rules

| Game | Easy / Normal / Hard |
| --- | --- |
| fifteen — Fifteen Puzzle | 30 / 90 / 180 random legal shuffle moves on a 4×4 board |
| pairs — Find the Pair | 9 / 12 / 18 pairs, preview 5 / 4 / 3 seconds, mismatch delay 0.7 s |
| math — Speed Math | 20 distinct problems, overall limit 60 s, 8 / 6 / 4 s per problem |
| chimp — Remember the Numbers | 5→12 / 6→18 / 9→24 numbers; maximum mistakes 4 / 3 / 2 |

Math pool: 992 / 6042 / 23880 distinct expressions. Commutative permutations
count as one expression. Four distinct options, exactly one correct; an answer
at the deadline boundary is rejected. Manual skipping is available.
In Remember the Numbers, numbers are hidden after selecting 1; choose in ascending
order. An error produces a new layout with the same count; success adds one number.

Load settings are increased by 50% relative to the original proposal;
this is not a medical/scientific difficulty assessment. Fifteen Puzzle is always
solvable; shuffle count is not the optimal solution length. A new start gets
a new layout, and the immediately preceding layout in the current module
session is not repeated.

Duration clocks are monotonic. UTC performed_at is only the start timestamp.
Back/Restart/focus loss/removal of an active scene ends the attempt as aborted.
Technical limits: 24 hours, 10000 events, 1 MiB server JSON. Approaching a limit
ends recording with recording_limit. Synthetic data is clearly labeled in the
game and report. There are no diagnoses or overall health score.

## Queue and recovery

Default data location: `user://zuma_minigames/`:

- pending — owner_key and immutable payload for each UUID;
- routes — profile/local URL fixed before sending;
- sent — original result, route, and confirmed server receipt;
- bindings.json — explicit immutable owner bindings;
- corrupt — damaged/incomplete files retained for recovery, never silently deleted.

Writing: temporary file in the same directory → flush/close → rename.
After restart, complete temporary files are recovered; corrupted files are
retained with a warning. Invalid nested bindings/receipts do not count as
successful delivery. A lost response is safe: the same UUID yields 200 with
the previous server ID. 409/422 preserve the record for diagnostics.
After the first network/5xx error, remaining records for that address are
skipped to avoid waiting through a timeout for each; records for other servers
continue sending. The next attempt is manual or triggered by a new result.

Switching profiles does not change old routes. If the queue could not be
written to disk, the payload is passed to the host through a signal and kept
in memory; fix the error and retry saving before closing the application.
Recovery after power-off cannot be guaranteed when the disk is physically unavailable.

Storage is designed for one process/one worker. The host application must
prevent multiple instances from using the same directory simultaneously.
SQLite and result files are not encrypted; the OS controls permissions.
Do not publish real data in Git. For backups, stop the application and copy
the entire queue directory together with server data.

## Checks

From the project root, substitute your Godot path:

```powershell
$godotExe = 'C:\Games\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
& $godotExe --headless --path . --script res://addons/zuma_minigames/tests/test_rules.gd 2>&1
& $godotExe --headless --path . --script res://addons/zuma_minigames/tests/test_module.gd 2>&1
& $godotExe --headless --path . --script res://addons/zuma_minigames/tests/test_outbox.gd 2>&1
& $godotExe --headless --path . --script res://addons/zuma_minigames/tests/test_recovery.gd 2>&1
& $godotExe --headless --path . --script res://addons/zuma_minigames/tests/test_profile_ownership.gd 2>&1
& $godotExe --headless --path . --script res://addons/zuma_minigames/tests/test_layout.gd 2>&1
```

`tests/export_runs.gd -- <absolute-output-dir>` generates 12 synthetic runs
for Go verification; `tests/playtest_ui.gd -- <absolute-output-dir>` completes
four Hard games using real GUI mouse events at 960×540 and takes screenshots.
It opens a test window; do not move the mouse during the automated run.
`test_delivery.gd` accepts JSON configuration and an offline/online phase;
the scenario is designed for separate test SQLite, not a working profile.

Exact API: [server documentation](../../server/docs/minigames.md).
