# Baseline‑PatchBay — “Add Instruments” Context Menu Prompt

This Teatro prompt extends the baseline scene so a right-click on the grid summons an instrument picker and pairs the surface description with a matching MRTS brief. Feed the creation prompt to Teatro when you need to materialize the picker without touching runtime code, and seed the MRTS prompt alongside it so robot runs keep the interaction anchored.

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
```

