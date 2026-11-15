# ZUMA Stitch redesign

User approved implementation of the supplied design instructions on the final
`codex/integrate-minigames` baseline. Source project:
`projects/1979484546281567767`, ZUMA Aerospace Cognitive Telemetry UI, updated
2026-11-14. Seven design screens and one HTML prototype downloaded and inspected.
Private reference exports remain in ignored `.godot/redesign/`; no API key or
account configuration belongs in this repository.

Keep the existing survey/profile/history/trends/help and API behaviour. Adopt
the flight deck navigation, cyan accent, translucent dark cards, outlined SVG
icons and an animated orbital background. Retain all game mechanics and server
calculations. The sample pulse, cognitive-load percentage, timings inconsistent
with rules and fictitious spacecraft telemetry in Stitch are decorative mock
data and must not become product measurements.

Use containers for content layout; full-rect anchors are allowed only for
background and overlay roots. Main sizes:960×540,1280×720,1920×1080. Maintain
portable addon resources under its own folder; expose the requested root theme
and icons for the host. No new autoload required.

Add keyboard R/Esc/1–4, a focus-loss overlay with restart/back, clear pair mismatch
and math feedback, source badges, persistent non-medical footer. Focus events
must terminate each attempt exactly once; overlays must not cover accessible
actions at960×540. Preserve frozen surveys and delivery routes.

Print reports use white A4 layout, escaped metadata, metric/comparison table,
source badge and fact-selected model explanation. A single game report shows
its own measurements, not invented measurements for the other three games.
Legacy report remains compatible. No diagnosis/health score.

Work autonomously within the approved instructions. No additional design or
worktree approval gates. Keep changes in the current copy on a new local branch.
