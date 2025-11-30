## midi2-browser — Agent Guide

What  
Lightweight web SPA (Vite + React) that mirrors an “Atlas-style” browser with MIDI 2.0 awareness. It can navigate pages via `semantic-browser` CDP endpoints and inspect/send UMP via `midi-service`. Ships with a midi2.js harness (git-pinned) for deterministic UMP encode/send.

How
- Install deps: `cd Public/midi2-browser && npm install`
- Dev: `npm run dev -- --host --port 4173` (adjust as needed)
- Env:
  - `VITE_SEMANTIC_BROWSER_URL` (default `http://127.0.0.1:8007`) — target for `/v1/snapshot`
  - `VITE_MIDI_SERVICE_URL` (default `http://127.0.0.1:7180`) — target for `/ump/send` and `/ump/events`
- Actions (UI):
  - Address bar → calls `/v1/snapshot` on semantic-browser and shows text + network preview.
  - “Send NoteOn” → encodes a MIDI 2.0 Note On via midi2.js, converts to UMP words, posts to `midi-service /ump/send`.
  - “Refresh UMP Tail” → fetches recent events from `midi-service /ump/events`.
- midi2.js dependency is pinned from git (`Fountain-Coach/midi2.git#v0.7.0:midi2.js`) because npm publishing is unavailable.

Rules
- FountainStore is the sole persistence backend for settings/logs (future wiring). No external search/index services.
- 3D/WebGL: only Three.js + Cannon.js allowed if visualizations are added; no other 3D stacks.
- No secrets in the repo; configure services via env.
