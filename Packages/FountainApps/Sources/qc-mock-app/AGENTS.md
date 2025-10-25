## AGENT — qc-mock-app (macOS)

Purpose
- A Quartz Composer–inspired macOS tool to mock graphs on a numbered grid.
- Edit nodes/ports/edges visually, then export LLM‑friendly specs:
  - JSON (`qc_prompt.json`) and DSL (`qc_prompt.dsl`).
  - Single‑transform canvas: one scale/translation applied to the entire scene.

Run
- Build/Run: `swift run --package-path Packages/FountainApps qc-mock-app`

Features
- Three panes: Outline | Canvas | Inspector. Canvas owns the full middle pane.
- Native gestures: two‑finger pan, pinch‑to‑zoom (via NSScrollView magnification).
- Single transform: one doc→view mapping (`CanvasTransform`) that all objects inherit.
- Nodes with draggable frames, rounded corners, and titles (doc‑space edits; snap on release).
- Ports on sides (left/right/top/bottom), typed (data/event/audio/midi).
- Edges (qcBezier) with control points computed in doc space.
- Numbered grid with scale‑aware decimation (hide minors/labels when zoomed out).
- Save/Load a “Kit” folder that contains JSON + DSL.

Tips
- Toggle Connect mode to wire ports; click again to cancel.
- Use the Inspector to edit node id/title/size/grid step; changes reflect immediately.
- Export writes two files: `qc_prompt.json` and `qc_prompt.dsl` into the selected folder.

Notes
- The app focuses on authoring + export; the DSL parser is not included here.
- The exported JSON matches the QC Prompt Kit schema used by `qclint.py`.

Design — Single Transform & Doc Space
- Canonical document space (artboard) expressed in logical units.
- `CanvasTransform { scale, translation }` supplies `docToView` / `viewToDoc` helpers.
- SceneContainer applies the transform once; Grid/Edges/Nodes render in doc units beneath it.
- Input converts view deltas to doc deltas via the same transform; snapping is doc‑space.
- Zoom anchors at the gesture centroid (keeps anchor under fingers).
- Non‑scaling strokes draw in an overlay or via inverse line width (1/scale).

Implementation roadmap
1) Introduce `CanvasTransform` and pass through environment.
2) Move all drawing under a single transformed container (or CALayer/MTKView root).
3) Convert gestures to use `viewToDoc` deltas for drag; snap in doc space.
4) Scale‑aware grid decimation and non‑scaling strokes for overlays.
5) Optional: switch Grid/Edges to Metal for dense graphs using the same transform.
