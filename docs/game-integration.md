# Protocol for future reaction and memory tasks

The four integrated minigames use a separate protocol and API: [minigames.md](../server/docs/minigames.md). This document applies only to future reaction and memory scenes.

The task launch button is hidden while the game scenes are absent from this project.
The application runs the games in sequence when both scenes are available;
before integration, agree on the `reaction-memory-v1` mechanics with the backend team.
Do not assign this protocol to a game with different mechanics merely to save it:
the server uses the version to select comparable previous results.

## Connecting scenes

Add `res://scenes/games/reaction.tscn` and `res://scenes/games/memory.tscn`.
Each scene root must inherit `Control` and declare the signals
`completed(result: Dictionary)` and `cancelled`. Upon successful completion,
emit `completed.emit(result)` with a result in the format below; on cancellation,
emit `cancelled.emit()`. Scenes are embedded in the application screen, so they
must not switch the main scene or submit the session themselves. The application
removes the scene afterward. Reaction runs first, followed by memory. Switching
sections or profiles is disabled during a task; “Cancel check” interrupts the
current check and returns to the survey.

The scene is placed inside a scrollable screen rather than occupying the entire
window. Its root receives the available width and a minimum height of 360 logical
pixels; a larger scene `custom_minimum_size.y` is preserved. Position game elements
relative to the root `Control`, use anchors, and set a larger minimum height if
needed. Do not assume the scene size matches the window size: users can scroll
on a small screen. Check input and the finished games' visual layout within
the application.

## Flow

1. Before launch, save the survey through the application screen and capture
   `profile_id` and `survey` specifically for this check. If the user cancels
   the task or switches profiles, do not create a full session.
2. The reaction game returns raw trials; the memory game returns correct and
   total trial counts. Both games must explicitly confirm the agreed protocol version.
3. After receiving both signals, the application saves the results to the queue.
   An alternative adapter can use this method on the application's root scene:

```gdscript
var outcome: Dictionary = app.accept_game_results(profile_id, survey, reaction, memory)
if outcome.ok:
    # The session is in the local queue. Show a send button or call
    # app.send_pending() for the currently selected profile.
    pass
else:
    # The result was not queued. Keep it in the game and show a clear error;
    # do not generate data or report success.
    print("Could not prepare session: ", outcome.error)
```

Example format (the numbers below are for tests only; do not use them as real data):

```gdscript
var survey = {"sleep_hours": 8.0, "fatigue": 0.0, "stress": 2.0, "mood": 7.0}
var reaction = {
    "protocol_version": "reaction-memory-v1",
    "trials": [{"outcome": "valid", "reaction_ms": 230},
               {"outcome": "premature"}, {"outcome": "missed"}]
}
var memory = {"protocol_version": "reaction-memory-v1", "correct": 3, "total": 4}
```

`valid` requires `reaction_ms` of 1–10000; `premature` and `missed` do not contain
`reaction_ms`. There must be 1–200 reaction trials and 1–1000 memory trials;
the correct-answer count is an integer from 0 to the total. The survey accepts
0–24 hours of sleep and 0–10 for other measures. Missing values are not replaced
with zeros.

## Queue and retries

Before sending, the client writes the full session with a UUID and UTC timestamp
to a separate file in `user://pending_sessions`. After completing both games,
the user can submit the check and immediately open its report. The button on
Overview sends all pending records for the selected profile. The file is deleted
after a confirmed 200/201 server response with the matching UUID and profile.
On an error, retry without changing the payload or UUID; the server handles an
identical retry without creating a duplicate. A 409 conflict leaves the record
in the queue and requires investigating the cause rather than generating a new UUID.

If the application cannot read the queue directory, validate a `.json` file,
or finds an incomplete `.json.tmp`, Overview displays a warning and the folder
path. These files are neither deleted nor sent automatically. Validated records
for the selected profile can still be sent; the warning remains until the
problem files are investigated. Before recovery, back up the entire folder;
do not edit UUIDs or data of sessions already submitted.

Data on disk is not encrypted. An unfinished game is not saved; testing with
the team's real scenes and server is still required.
