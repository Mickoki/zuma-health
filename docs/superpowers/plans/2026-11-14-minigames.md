# Zuma Minigames Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Four portable Godot games, durable offline delivery, compatible Go storage/replay/reports/Ollama.
**Architecture:** Addon scenes and local rule engine emit immutable event logs; Go independently replays them. New game-runs endpoints coexist with legacy sessions.
**Tech Stack:** Godot 4.7.2 GDScript, Go 1.26+, SQLite, Ollama qwen3:8b.
**Spec:** `docs/superpowers/specs/2026-11-14-minigames-design.md` (approved including randomization and parameter increases).

## Global Constraints

- Work inline on feat/minigames-module in current folder, explicitly authorized. No additional permission checkpoints, no push/merge.
- Do not stage user project.godot edits or server/examples/client.gd.uid.
- Addon self-contained under addons/zuma_minigames; no main_scene, Autoload, InputMap changes.
- Defaults: fifteen shuffle30/90/180; pairs9/12/18 preview5000/4000/3000 mismatch700; math20, total60000, question8000/6000/4000 with enlarged operands; chimp5→12/6→18/9→24 and mistakes4/3/2.
- New run body1MiB/events10000/duration24h; old session body256KiB unchanged.
- Legacy API/tests preserved; schema1→2 migration preserves old data.
- UTC start metadata, monotonic millisecond events; null is not zero; no clinical claims.

## Review Focus

- Lost success response/restart must replay same UUID without wrong-profile delivery (Task5).
- Inputs at/after math deadline become timeout, not accepted answer (Tasks1,4).
- Focus loss/removal/restart emits exactly one aborted result (Tasks4,6).
- A typical chimp mistake-limit loss still has comparable history (Tasks1,2).
- Backfill invalidates new explanations and model slot is shared with legacy generation (Task3).

## Files and Interfaces

- `server/internal/games/{types,rules,fifteen,pairs,math,chimp,report}.go`: pure validation/replay, metrics, comparisons, facts.
- `games.Input`: client_run_id, game_id, rules_version, difficulty, config, source, performed_at, status, finish_reason, duration_ms, initial, events.
- `games.Event`: kind, t_ms; index for move/flip/click/answer and math show; positions for chimp show; finish/skip/timeout have no extra data. First math/chimp show at t=0; final finish at duration_ms.
- Initial union: fifteen `{board,scramble}`, pairs `{cards}`, math `{questions:[{op,a,b,options}]}`, chimp `{}` (round layouts in show events).
- `games.Defaults(game,difficulty) (map[string]int,error)`, `games.Validate(Input,time.Time) (Metrics,error)`, `games.Calculate(Run,*Run) Report`, `games.Facts(Report) []domain.Fact`, `games.Fingerprint(Report) string`.
- `server/internal/store/game_runs.go`: SaveGameRun/GetGameRun/ListGameRuns/BaselineGameRun and explanation caching. `migrations.go`: schema2.
- `model.Client.ExplainFacts(ctx,[]domain.Fact)` is shared by old Explain and new endpoint; same semaphore.
- `server/internal/httpapi/game_runs.go`: new routes from spec; existing decoder gains per-route body limit. `game_report.go`: escaped HTML.
- `addons/zuma_minigames/core/{rules,generator,outbox,transport}.gd`: local game state, RNG, storage, HTTP; scoped preloads, no global names.
- `addons/zuma_minigames/{module,game_view,demo}.gd` and `.tscn` scenes: public host, four game scenes, demo UI, own theme.
- `addons/zuma_minigames/tests/`: headless tests, scripted UI scenarios, export of event fixtures for Go.
- `addons/zuma_minigames/README.md`, `server/docs/{openapi.yaml,minigames.md}`, `docs/minigames-verification.md`: API, copy/start examples and evidence.

## Task 1 — Pure Go game contract and replay

- [x] Write tests for hand-checked completed and aborted logs for all four games; invalid board/move/pair timing/math option/deadline/chimp sequence; missing numeric fields, timestamps and limits. Known fixtures: pairs9 perfect→9 attempts/0 errors; math all20 correct→100%; chimp maximum18; fifteen reverse30 scramble→30 moves solved.
- [x] `go test ./internal/games` must fail for missing API.
- [x] Implement types/defaults and four replayers. Strict per-game initial/events, exactly configured values, exact terminal condition. Config canonicalized and report metric units explicit.
- [x] `go test ./...` must pass. Commit.

## Task 2 — Storage, migration, comparison

- [x] Tests: migrate populated schema1 (profile/session/ready explanation), reopen; game UUID replay/conflict/concurrency; baseline by time/game/config/source/eligible outcome; chimp loss vs loss, aborted excluded.
- [x] Observe missing methods/schema failures.
- [x] Implement schema2 tables/indexes and transactional storage. Canonical JSON eliminates object-key order dependence. Build game comparison and server-authored facts; unavailable deltas null.
- [x] Full Go suite PASS; commit.

## Task 3 — API, HTML, model reuse

- [x] Tests: four new run HTTP workflows, old limit256KiB vs new1MiB, filters/pagination, invalid payloads, HTML escaping, backfill cache invalidation; common generation slot and model failure/cancellation.
- [x] Observe missing routes failing.
- [x] Implement routes/HTML. Refactor old Explain to ExplainFacts retaining old signature and behavior. Recheck latest fingerprint after generation; preserve good cached explanation on failure.
- [x] Full Go suite/vet/build PASS; extend OpenAPI with precise per-game union/examples. Commit.

## Task 4 — Godot game logic and UI

- [x] Write headless test script for generators and deterministic action traces, state transitions and terminal behavior. First run fails on missing addon scripts.
- [x] Implement local generators with scoped RNG and no immediate layout repetition. Rules mirror documented mechanics while Go stays independently implemented.
- [x] Implement own Control-based four scenes, shared view and module API/signals; instructions/start/result/restart/exit, difficulty, preview/deadlines/hide numbers, focus-loss abortion. Russian UI works960×540 and1280×720.
- [x] Godot import/check/headless tests pass; generated fixtures accepted by Go. Copy addon only into isolated temporary project and test without host dependencies. Commit.

## Task 5 — Durable outbox and demo integration

- [x] Headless filesystem/HTTP tests: unknown owner profile, disk error, damaged/incomplete file, restart, 201/200 receipt, lost response, 409/422 retention, profile change and sequential worker.
- [x] Observe missing outbox/transport failures.
- [x] Implement per-run temp→flush→close→rename storage, separate explicit owner binding, immutable payload, sent receipt and recovery. Delivery errors visible. No tight retry loop.
- [x] Demo profile selection/creation, explicit binding, pending counter/retry, local results independent of network. Full Godot→API→SQLite tests for four games; offline then restart/retry produces one run. Commit.

## Task 6 — Runtime verification, docs, independent review

- [x] Run/render and play all four scenes via scripted UI and native UI inspection, including960×540; capture evidence. Unit logic alone is insufficient.
- [x] Real qwen3:8b explanation for a new-game report; no-model scenario keeps complete flow available. Validate report facts and printed HTML.
- [x] Final gofmt/vet/test/build(CGO0), Godot import/headless/integration; document exact commands/evidence and limitations.
- [x] README/API/examples explain copying addon, signals, configurations, outbox binding/recovery and backup/migration.
- [x] One fresh read-only whole-branch reviewer; fix material findings with regression tests. Completion audit against all spec sections, commit final evidence. No further approvals needed within scope.

## Rulings and execution

User explicitly approved autonomous inline execution and current checkout. This overrides skill checkpoints asking for another plan/execution/worktree approval. Use PowerShell and a ledger under `.superpowers/sdd/2026-11-14-minigames/` instead of POSIX helper scripts. Baseline: existing Go suite PASS; installed Godot4.7.2.
