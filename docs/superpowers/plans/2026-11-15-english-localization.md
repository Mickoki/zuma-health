# English localization implementation plan

User request: make the entire interface and all project files English.
Baseline: Stitch redesign c475c48. Branch: codex/english-localization.

Translate all tracked human-facing text, documentation, test fixtures, comments,
errors, print reports and model instructions. Keep wire identifiers, URLs,
SQLite schemas, mathematical operators and user-authored saved data intact.
Cached explanations from previous versions must not surface old Russian facts
as if they were current English explanations; validate existing fingerprinting.
No credentials, private Stitch exports or user data enter the repository.

- [x] Translate backend/runtime/report/model text and server documentation.
- [x] Translate root/project documentation and historical specifications.
- [x] Translate client/addon text and align UI tests with English labels.
- [x] Scan all tracked text for Cyrillic, run Go/Godot/integration/model tests.
- [x] Inspect English layouts, export client/server and English Windows package.
- [x] Record validation and commit locally.
