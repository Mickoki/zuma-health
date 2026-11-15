# ZUMA Stitch Redesign Implementation Plan

> Execute inline with superpowers:executing-plans. User authorized the supplied design.

**Goal:** Apply Stitch visuals to the integrated Godot app and Go print reports.
**Architecture:** Portable shared UI assets/theme in addon; host uses its theme
and background. Existing state/API code remains authoritative. Report styling
is shared CSS with separate existing data templates.
**Tech:** Godot4.7.2/GDScript/shader/SVG, Go html/template.
**Spec:** ../specs/2026-11-15-stitch-design.md.

- [x] Add regression checks for focus overlay, keyboard, source colours and layout; observe missing feature failures.
- [x] Implement orbital shader, themes, icons; apply host/sidebar/cards and demo styling without removing pages.
- [x] Implement game presentation, mismatch/math feedback, focus overlay and keyboard controls; rerun rule/module/layout tests.
- [x] Restyle escaped print reports with A4 CSS and factual tables; run Go tests/vet/build and HTML checks.
- [x] Fix the already reproduced test harness defects (missing addon copy; pairs test waiting against a different clock) so verification is repeatable.
- [x] Full client/addon/real-server/model tests, rendered states at three sizes, exported EXE smoke test. Document evidence and limitations; commit locally.
