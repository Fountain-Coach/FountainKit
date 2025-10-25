## AGENT — qc-mock-app (macOS)

Purpose
- A Quartz Composer–inspired macOS tool to mock graphs on a numbered grid.
- Edit nodes/ports/edges visually, then export LLM‑friendly specs:
  - JSON (`qc_prompt.json`) and DSL (`qc_prompt.dsl`).

Run
- Build/Run: `swift run --package-path Packages/FountainApps qc-mock-app`

Features
- Numbered grid (configurable step) and axes labels.
- Nodes with draggable frames, rounded corners, and titles.
- Ports on sides (left/right/top/bottom), typed (data/event/audio/midi).
- Edges (qcBezier) by clicking port → port in Connect mode.
- Save/Load a “Kit” folder (choose directory) that contains JSON + DSL.

Tips
- Toggle Connect mode to wire ports; click again to cancel.
- Use the Inspector to edit node id/title/size/grid step; changes reflect immediately.
- Export writes two files: `qc_prompt.json` and `qc_prompt.dsl` into the selected folder.

Notes
- The app focuses on authoring + export; the DSL parser is not included here.
- The exported JSON matches the QC Prompt Kit schema used by `qclint.py`.

