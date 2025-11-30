# MIDI2 Browser — North Star Plan (Atlas-style)

Goal  
Build a “true” web browser experience, optimized for MIDI 2.0 interactions via `midi2.js`, using only the `Public/` web stack. Think OpenAI’s Atlas, but with MIDI 2.0‑aware controls, deterministic networking, and instrument hooks.

Scope (v0)
- Browser shell in the web app (no Electron): tab bar, address bar, navigation buttons, session history.
- MIDI 2.0 session layer via `@fountain-coach/midi2`:
  - Deterministic clocks/schedulers exposed to the page via a small injected harness.
  - UMP capture/inspection pane (per tab) with filterable streams.
  - PE/CI helpers: encode/decode SysEx7/8, profile/property operations, chunking utilities.
- Page instrumentation:
  - CDP/WebView integration reused from `semantic-browser` patterns for DOM snapshots, screenshots, network capture.
  - Optional midi2.js injection into target pages for deterministic timing and event hooks (opt-in per tab).
- Safety/bounds: no external engines beyond Three.js + Cannon.js if 3D is needed for visualizations; no CoreMIDI/UIkit; FountainStore for persisted settings/logs only.

Architecture
- Frontend: new SPA under `Public/midi2-browser/` (Vite/TS). Components:
  - `TabManager`, `AddressBar`, `NavControls`, `UMPConsole`, `NetworkPanel`, `DOMPreview`, `Midi2HarnessControls` (toggle injection, clocks, profile/PE helpers).
  - State store (e.g., Zustand/Redux-lite) with per-tab session + persisted settings (FountainStore round-trip optional).
- Backend hooks:
  - Reuse `semantic-browser-server` for CDP navigation/snapshots when available (`SB_CDP_URL`).
  - MIDI service (`midi-service`) for UMP send/record endpoints; store UMP logs to `.fountain/corpus/ump`.
- Persistence:
  - FountainStore corpus `midi2-browser` for settings and saved sessions (tabs, favorites, MIDI routing presets).
  - No Typesense/Elastic; FountainStore is the single backing store.

MVP checklist
1) Scaffolding: create `Public/midi2-browser/` Vite app, base layout (tab strip, address bar, main pane, right rail for UMP/DOM panels).
2) Navigation: wire address bar → CDP fetch via `semantic-browser` endpoint; render DOM/text/screenshot preview; basic history.
3) MIDI 2.0 harness: bundle `@fountain-coach/midi2@0.7.0`; expose encode/decode, scheduler, PE/CI helpers; add opt-in page injection toggle.
4) UMP console: live view of sent/received UMP (loopback via midi-service); filters by group/type; record to FountainStore corpus when enabled.
5) Settings: persist tab list and MIDI routing prefs to FountainStore (`midi2-browser` corpus).
6) Hardening: sandbox unknown pages (no credential prompts), size/time limits on captures, explicit 503 if backend services absent.

Out of scope (for now)
- Electron/native wrappers.
- Third-party search/index; only direct navigation and service-backed capture.
- Non-Three/Cannon 3D or alternate MIDI engines.

Next steps
- Confirm app ID (`midi2-browser`) and corpus naming.
- Scaffold `Public/midi2-browser/` with Vite + TS; add `AGENTS.md` with envs and launch commands.
- Add minimal UI skeleton: tab bar, address bar, main content, UMP side panel.
- Wire CDP fetch via `semantic-browser` endpoint; stub midi2.js harness module and UMP console pane.
