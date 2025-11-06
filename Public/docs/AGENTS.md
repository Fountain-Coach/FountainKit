## Public/docs — Agent Guide (Docs Publishing)

This folder hosts human‑readable docs for publishing. Keep content narrative‑first with stable file anchors reviewers can jump to.

Principles
- Why → How → Where ordering. Open with a short paragraph; keep lists tight and actionable.
- Stable anchors: include real file paths (e.g., `Packages/FountainApps/Sources/metalviewkit-runtime-server/*`).
- Commands inline: prefer one‑liners with backticks; avoid long fenced blocks when possible.
- Avoid duplication: link to the canonical OpenAPI spec or source directory instead of restating.

Docs index
- MVK runtime overview: `Public/docs/MVK-Runtime.md` (HTTP runtime surface, examples, smoke instructions).
- MIDI transport status: `Public/docs/MIDI-Transport-Status.md` (Loopback/CoreMIDI/RTP and current defaults).

Maintenance
- Keep these docs in sync with curated specs under `Packages/FountainSpecCuration/openapi/**` and with server code in `Packages/FountainApps/Sources/**`.
- When adding a new public doc, update `Public/AGENTS.md` with a one‑line link under “Runtime docs”.
