# AGENT — FountainFlow (per‑node flexible node editor)

FountainFlow is our evolution path from AudioKit’s Flow toward a per‑node‑flexible editor that can render Stage nodes as pages (node = page) with baseline‑aligned ports and custom bodies, while keeping Flow’s solid wiring and gestures.

What
- A SwiftPM library exporting `FountainFlow`.
- Starts as a thin interop layer over Flow; grows native capabilities where Flow’s global layout limits us.

Why
- Flow has global layout/style (one `LayoutConstants`, one `Style`) and always draws a node body. We need per‑node width/height, body rendering hooks, and input/output rect providers.

How (incremental)
- v0 Bridge (this repo):
  - Types for per‑node style and rect providers (protocols).
  - Helpers to hide node bodies for selected kinds (e.g., Stages) and render custom bodies on top of the canvas.
- v1 Native:
  - `NodeStyleProvider` and `NodeRectProvider` drive the editor.
  - `NodeBodyRenderer` draws bodies; Flow remains only for wire gestures if useful.

Where it’s used
- PatchBay Studio Stage nodes: ports align to baselines; the page is the node body; no Flow tile.

Conventions
- Snapshot/UI invariants required; golden images under `Tests/**/Baselines`.
- Numeric invariants: fit/center, baseline spacing, left edge alignment to ports.

