# Baseline‑PatchBay — Add Instruments (Deprecated)

This document described a right‑click “Add Instruments” context menu and its Teatro/MRTS prompts. We rolled this feature back: the baseline web surface cannot rely on right‑click and the baseline macOS app does not ship this menu. Use the new three‑pane baseline instead.

What to use now
- Baseline layout: three vertical panes with the canvas instrument centered and draggable gutters.
- Prompts: seeded and printed on boot by `grid-dev-app`.
  - Creation prompt: see `Packages/FountainApps/Sources/grid-dev-app/AppMain.swift:buildTeatroPrompt()`.
  - MRTS prompt: see `Packages/FountainApps/Sources/grid-dev-app/AppMain.swift:buildMRTSPrompt()`.
- PE controls for layout: `layout.left.frac`, `layout.right.frac` (0..1), emit `ui.layout.changed`.

Where
- Baseline app: `Packages/FountainApps/Sources/grid-dev-app/` (launcher `Scripts/apps/baseline-patchbay`).
- Robot tests: `Packages/FountainApps/Tests/PatchBayAppUITests/*` (grid/contact/monitor suites).

Note: The historical content of this file is kept below for reference but is no longer authoritative.

What (historical)
- Right‑click “Add Instruments” picker. Superseded by the three‑pane baseline.

Why
- The Baseline app is authoritative for viewport/math invariants. Any UI change (like the picker) must carry an updated Teatro prompt and an MRTS brief. We seed both into FountainStore for provenance and robot runs.

How (historical)
- Spec‑first updates for instrument kinds and seeders; superseded.

Where
- Curated spec: `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`
- Service spec: `Packages/FountainApps/Sources/patchbay-service/openapi.yaml`
- App UI: `Packages/FountainApps/Sources/patchbay-app/**`
- Seeders: `Packages/FountainApps/Sources/baseline-robot-seed`, `Packages/FountainApps/Sources/grid-dev-seed`
- Tests/snapshots: `Packages/FountainApps/Tests/PatchBayAppUITests/**` and `…/Baselines/`
- Recorder + headless (for Web/Linx): `Packages/FountainServiceKit-MIDI/AGENTS.md`

## Creation Prompt

```text
Scene: GridDevApp (Grid‑Only with Persistent Corpus)
Text:
- Window: macOS titlebar window, 1440×900pt. Content background white (#FAFBFD).
- Layout: single full‑bleed canvas; no sidebar, no extra panes, minimal chrome.
- Only view: “Grid” Instrument filling the content.
  - Grid anchoring: viewport‑anchored. Leftmost vertical line renders at view.x = 0 across all translations/zoom. Topmost horizontal line at view.y = 0.
  - Minor spacing: 24 pt; Major every 5 minors (120 pt). Minor #ECEEF3, Major #D1D6E0. Crisp 1 px.
  - Axes: Doc‑anchored origin lines (x=0/y=0) in faint red (#BF3434) for orientation.
- MIDI 2.0 Monitor pinned top‑right (non‑interactive); fades out after inactivity; wakes on MIDI activity.
- Cursor Instrument (always on): crosshair + ring + tiny “0” rendered at the pointer; label offset so it never occludes the zero.
  - Grid coordinates: g: col,row where
    • doc = (view/zoom) − translation
    • leftDoc = 0/zoom − tx, topDoc = 0/zoom − ty
    • col = round((doc.x − leftDoc)/step), row = round((doc.y − topDoc)/step)
    • step = grid.minor
- Context menu Instrument: right-click anywhere on the Grid summons “Add Instruments”.
  - Presentation: anchored popover near the pointer (12 pt offset down/right), 320 pt wide, floating above the canvas with subtle drop shadow (#00000014) and rounded corners (12 pt).
  - Content: scrollable container listing available instruments (“Canvas Grid”, “MIDI Monitor”, “Cursor”, “Baseline Presets”, future entries).
    • Each row: 40 pt tall, left glyph circle (#D1D6E0) with instrument initial, instrument name (SF Pro, 13 pt, weight medium), secondary description (11 pt, #6E7683), and a trailing “Add” capsule button.
    • Rows highlight #F1F4FA on hover and close after clicking “Add”.
  - Dismissal: clicking outside, pressing Esc, or selecting an instrument closes the popover.
```

## MRTS Prompt

```text
Scene: Baseline‑PatchBay — “Add Instruments” Context Menu (MRTS)
Text:
- Objective: extend the baseline robot run so it verifies the right-click “Add Instruments” picker on the grid canvas.
- Output: update the `Scripts/ci/baseline-robot.sh` workflow (or companion XCTest in `PatchBayAppUITests`) to add a deterministic step that:
  • Launches the Baseline‑PatchBay app in robot mode and right-clicks the grid at doc coordinates (0,0).
  • Asserts a popover opens 12 pt down/right from the pointer, sized 320 pt wide with rounded 12 pt corners and drop shadow opacity 0.08.
  • Scrolls the picker (if needed) and verifies that the list includes “Canvas Grid”, “MIDI Monitor”, “Cursor”, and “Baseline Presets”, each row 40 pt tall with hover color #F1F4FA and trailing “Add” capsule.
  • Clicks “Add” on “Baseline Presets” and confirms the picker dismisses while dispatching the instrument activation event.
  • Clicks outside the grid to confirm the popover dismisses without errors and logs a closure event.

Numeric invariants:
- Context menu is anchored to the pointer and offsets exactly (12 pt, 12 pt).
- Picker width locked at 320 pt; content scroll frictionless with no elastic bounce.
- Row typography: title SF Pro 13 pt medium; subtitle 11 pt regular with #6E7683.
- Robot logs include `mrts.addInstruments.open`, `mrts.addInstruments.added`, and `mrts.addInstruments.dismissed` markers in order.

Tolerances and spaces
- Treat view‑space values with ±0.5 pt tolerance in numeric checks (anti‑aliasing, DPI rounding).
- Use the canonical transforms for conversions: `doc = (view/zoom) − translation`.

Robot wiring (MIDI 2.0 and events)
- Preferred: drive via dedicated vendor‑JSON ops (for parity with Web MRTS and Linux/headless):
  - `ui.contextMenuAt { "view.x": <px>, "view.y": <px> }` → opens picker (anchored offset 12 pt, 12 pt).
  - `ui.addInstrument { "kind": "<instrumentKind>" }` → adds the selected instrument and closes the popover.
- If the UI path is used in XCTest, still emit the same log markers (`mrts.addInstruments.*`) so recorder traces remain comparable across platforms.

Snapshot policy (visual regression)
- Sizes: 1440×900 and 1280×800; store baselines under `Packages/FountainApps/Tests/PatchBayAppUITests/Baselines`.
- Rebaseline only after numeric invariants pass: run `Scripts/ci/ui-rebaseline.sh`.

MRTS facts (seeded)
```json
{
  "product": "baseline-patchbay",
  "tests": ["AddInstrumentsContextMenuTests"],
  "vendorJSON": ["ui.contextMenuAt", "ui.addInstrument"],
  "invariants": [
    "pickerAnchoredOffset12pt",
    "pickerWidth320pt",
    "rowHeight40pt"
  ]
}
```

Commands (scan‑friendly)
- Build service: `swift build --package-path Packages/FountainApps -c debug --target patchbay-service`
- Seed MRTS prompt: `swift run --package-path Packages/FountainApps baseline-robot-seed`
- Enum drift check: `bash Scripts/ci/check-patchbay-spec-sync.sh`

Routes (reference)
- PatchBay (OpenAPI): `/instruments` (CRUD), `/instruments/{id}/schema`, `/canvas/zoom`, `/canvas/pan`
- MIDI service (OpenAPI, for Web/Linux): `POST /ump/send`, `GET /ump/events`, `POST /ump/events`, `GET/POST/DELETE /headless/instruments`
MRTS facts (seeded)
```json
{
  "product": "baseline-patchbay",
  "tests": ["AddInstrumentsContextMenuTests"],
  "vendorJSON": ["ui.contextMenuAt", "ui.addInstrument"],
  "invariants": [
    "pickerAnchoredOffset12pt",
    "pickerWidth320pt",
    "rowHeight40pt"
  ]
}
```

Commands (scan‑friendly)
- Build service: `swift build --package-path Packages/FountainApps -c debug --target patchbay-service`
- Seed MRTS prompt: `swift run --package-path Packages/FountainApps baseline-robot-seed`
- Enum drift check: `bash Scripts/ci/check-patchbay-spec-sync.sh`

Routes (reference)
- PatchBay (OpenAPI): `/instruments` (CRUD), `/instruments/{id}/schema`, `/canvas/zoom`, `/canvas/pan`
- MIDI service (OpenAPI, for Web/Linux): `POST /ump/send`, `GET /ump/events`, `POST /ump/events`, `GET/POST/DELETE /headless/instruments`
```
