## AGENT — qc-mock-app (macOS) — DEPRECATED

This app is deprecated in favor of the CI/PE‑first PatchBay Studio. It remains runnable for learnings and export demos. See `Packages/FountainSpecCuration/openapi/v1/patchbay.yml` for the current service.

qc‑mock‑app is a Quartz Composer–inspired macOS tool to sketch graphs on a numbered grid and export LLM‑friendly specs — JSON (`qc_prompt.json`) and a compact DSL (`qc_prompt.dsl`). The canvas uses a single transform (`CanvasTransform { scale, translation }`) applied once to the scene; everything renders and snaps in document space. Gestures are native (pan/zoom), edges are qcBezier curves in doc space, and the grid decimates labels as you zoom out.

The app conforms to the `qc-mock-service` API (see `Sources/qc-mock-service/AGENTS.md`). Don’t add UI that can’t be represented by service endpoints; when feasible, route state changes via the service to keep parity (import/export/zoom/pan/CRUD). Build and run with `swift run --package-path Packages/FountainApps qc-mock-app`.

Tips: toggle Connect mode to wire ports; click to cancel. Use the Inspector to edit node id/title/size/grid step. Export writes `qc_prompt.json` and `qc_prompt.dsl` into the chosen folder. The DSL parser is not included here; the JSON matches the QC Prompt Kit schema used by `qclint.py`.
