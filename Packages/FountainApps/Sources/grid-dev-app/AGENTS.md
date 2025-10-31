# Baseline‑PatchBay (grid‑dev‑app) — Agent Guide

What/Why
- Baseline‑PatchBay is the default baseline UI for FountainAI apps. It is a grid‑only, instrument‑first surface used to calibrate viewport math and define MIDI Robot invariants.
- Changes to this app set expectations for all downstream UIs. Therefore every change MUST be paired with a matching MRTS (MIDI Robot Test Script) Teatro prompt that encodes the numeric invariants and robot coverage.

Behavior (boot policy)
- On boot, the app:
  - Seeds its creation Teatro prompt into FountainStore (page `prompt:grid-dev`).
  - Prints both prompts to stdout: creation prompt AND the MRTS prompt.

How (launch/seed/test)
- Launch (recommended): `Scripts/apps/baseline-patchbay` (or `Scripts/dev/dev-up --check` which auto‑launches it).
- Window title can be overridden via `APP_TITLE` (defaults to `Baseline‑PatchBay`).
- Persist MRTS prompt into the corpus: `swift run --package-path Packages/FountainApps baseline-robot-seed`.
- Run baseline robot tests: `Scripts/ci/baseline-robot.sh`.

PE knobs (observability)
- Monitor overlay: `monitor.fadeSeconds`, `monitor.opacity.min`, `monitor.maxLines`, `monitor.opacity.now`.
- Reset button (fade/wake): `reset.fadeSeconds`, `reset.opacity.min`, `reset.opacity.now`, `reset.bump`.

Invariants (must hold)
- Default transform: `zoom=1.0`, `translation=(0,0)`.
- Left grid contact pinned at `view.x=0` across translations/zoom.
- Minor spacing px = `grid.minor × zoom`; major spacing = `grid.minor × majorEvery × zoom`.
- Anchor‑stable zoom drift ≤ 1 px.
- Right edge contact index = `floor(view.width / (grid.minor × zoom))` at `x = index × step`.
- Monitor emits `ui.zoom`/`ui.pan` (and debug) on zoomAround/pan/reset.

Files/commands
- App entry: `Packages/FountainApps/Sources/grid-dev-app/AppMain.swift` (prints creation + MRTS prompts on boot).
- MRTS seeder: `Packages/FountainApps/Sources/baseline-robot-seed/main.swift`.
- Robot runner: `Scripts/ci/baseline-robot.sh`.
- Launcher: `Scripts/apps/baseline-patchbay`.

