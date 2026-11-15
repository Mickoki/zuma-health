# Interface cleanup verification

Date: November 15, 2026. Baseline: English localization55244af.
Branch: `codex/clean-interface`.

Removed decorative navigation captions, numbered section labels and repeated
introductory text. Overview now concentrates on the next action. It shows
profile creation first when no profile exists; existing profile controls and
the latest legacy check-in can be expanded when needed. Storage diagnostics
remain available under Help. Survey ranges, detailed Help, meaningful errors,
history/report access and source badges are retained.

Game rules and parameters are shown before Start. Active play shows the field,
live counters and actions. Results replace live counters with a single summary,
using seconds for total duration; recorded millisecond data is unchanged.
The interruption overlay hides duplicate background summary/disclaimer text.
Restart restores counters, actions and the foreground disclaimer.

The game hub and standalone demo use shorter introductions. Empty queue counts
are hidden in the demo; important pending/error messages remain visible.
The chart's ordering explanation is available as a tooltip and in Help.
The interface remains English. No server/API/storage/game-rule changes.

Validation:

- Eleven client integration suites: PASS.
- Seven addon suites, including keyboard/focus and compact layout: PASS.
- English locale/navigation/disclaimer layout at960/1280/1920: PASS.
- New `tests/clean_interface.gd`: rules before Start, no repeated active rules,
  no duplicated result counters, restart/focus state, profile disclosure and
  relocated diagnostics remain accessible: PASS.
- Four hard games completed through rendered GUI mouse events at960×540:
  PASS, no errors in the final log.
- Forty-eight rendered states at960×540,1280×720,1920×1080: PASS. Representative
  Overview, hub, active fields and results inspected.
- Source English guard and diff checks: PASS.
- Independent read-only review: no material findings.
- Windows client exported and smoke-tested; package includes the unchanged
  English backend and launch instructions. It is unsigned.

Local screenshots and logs are under ignored `.godot/clean-ui/` and
`.godot/english/clean-*`. The package is `builds/windows/Zuma-Clean-Windows.zip`.
