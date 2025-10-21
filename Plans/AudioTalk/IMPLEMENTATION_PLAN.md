# AudioTalk — Implementation Plan (Polish to Product)

This plan takes the current repository state to a polished, chat‑driven AudioTalk product, fully aligned with FountainAI’s OpenAPI‑first, Planner + Tools orchestration, and modular kits.

Scope anchors
- Specs are authoritative in `Packages/FountainSpecCuration/openapi/v1/audiotalk.yml`.
- AudioTalk service code lives in `Packages/FountainServiceKit-AudioTalk`.
- Apps (server/CLI/Studio) live in `Packages/FountainApps`.
- No generated sources are committed; `swift build` regenerates.

Current status (baseline)
- Persistence wired via `FountainStoreClient` with corpus `audiotalk` and collections for screenplay, notation, dictionary, macros, cues, and journal.
- Screenplay API backed by real data: GET/PUT source (ETag), parse (model), map‑cues, cue‑sheet (JSON/CSV/PDF), SSE parse stream.
- Bridge implemented: apply screenplay cues → notation (ETag‑aware) with Lily mapping; journaling of `parsed`, `cue_mapped`, `plan_applied`.
- CLI covers screenplay/notation/journal; one‑click scripts boot server and smoke.
- Tools integration: ToolsFactory registers OpenAPI as tools; FunctionCaller supports templated paths + base prefix.

Product goals
- Chat‑first studio (“AudioTalk Studio”): users instruct verbally; Fountain + Lily update live with visible anchors and previews.
- Deterministic, resumable sessions with ETags and a durable Journal.
- OpenAPI‑first across all surfaces and tool orchestration (Planner + Tools).

Milestones (M1 → GA)

M1 — Core polish (API, persistence, cues)
- Finalize spec enums and content types; ensure `JournalEvent` types (parsed, cue_mapped, plan_applied) are complete.
- Persist parsed model keyed by ETag; prefer cached results across parse/map.
- Cue sheet CSV/PDF parity (headers, pagination, simple styling).
- Acceptance: Endpoints green; CLI flows stable; CI smoke passes.

M2 — Tools catalog + Planner orchestration
- Register AudioTalk OpenAPI via ToolsFactory (`Scripts/register-audiotalk-tools.sh`); corpus `audiotalk`.
- Configure FunctionCaller with `FUNCTION_CALLER_BASE_URL` (local: `http://127.0.0.1:8080/audiotalk/v1`).
- Author Planner prompt/profile for AudioTalk tasks; verify `reason → execute` calls tools deterministically.
- Acceptance: Given “map cues and apply to notation”, Planner returns function steps and FunctionCaller mutates Lily (ETag respected).

M3 — AudioTalk Studio (chat‑driven GUI)
- Add Studio tab in `FountainLauncherUI`:
  - Chat panel (EngraverChatCore) targeting Planner + FunctionCaller.
  - Fountain editor (syntax, tag helpers) bound to GET/PUT screenplay.
  - Lily editor + preview (render) bound to GET/PUT/render.
  - Journal timeline panel consuming `/audiotalk/journal` + stream.
- Acceptance: Typing “parse screenplay and map cues” updates model/cue list and Lily source; Journal shows events.

M4 — Anchors & selection sync
- Insert stable Lily anchor markers on apply (e.g., `% AT_ANCHOR id=... sc=3 ln=42`).
- Add `scan-anchors` endpoint to parse Lily and persist an anchor map (script↔notation).
- Selection sync: clicking a tag/scene highlights the Lily anchor region and vice versa.
- Acceptance: Moving Lily content and re‑scanning updates anchor map; UI selection sync remains correct.

M5 — Rendering & streaming
- Improve SSE: expose live Journal stream and parse events in Studio (transport: NIO chunked, no buffering).
- Rendering polish: SVG default, PDF export from cue sheet.
- Acceptance: Long‑lived SSE keeps chat + panels in sync without manual refresh.

M6 — Quality, tests, and CI
- Unit/golden tests: ScreenplayParser, cue mapping heuristics, Lily mapping, PDF builder, ETag concurrency.
- Add CI smoke for screenplay flows (health, dictionary, ETag, parse/map/apply, cue‑sheet).
- Lint OpenAPI; ensure all touched packages compile with `swift build`.
- Acceptance: All CI jobs green; no generated sources committed.

M7 — Beta → GA
- Docs: user guide (Studio), API reference, CLI examples, tool orchestration notes.
- Telemetry: metrics for tool invocation latencies, apply success/conflicts, SSE subscribers.
- Crash/edge handling: robust errors for missing sessions, bad markers, invalid Lily.
- Acceptance: Trial users complete core tasks via chat without manual CLI.

Detailed backlog (by workstream)

Specs
- Extend `JournalEvent.type` (done) and document values.
- Add `AnchorMap` schemas and endpoints: `scan-anchors`, `get anchors`, `reanchor`.
- Document Lily marker format and stability guarantees.

Service
- ScreenplayParser warnings coverage; characters heuristics toggleable via request flags.
- Cue mapping options (`theme_table`, hints) influence plans; persist mapping options alongside cues.
- Lily mapping: expand beyond comments—dynamics/tempo handled, add articulation/macros as Lily.
- SSE transport: enable chunked responses in NIO transport for truly live streaming.

Studio (SwiftUI)
- Chat bound to Planner + FunctionCaller; tool outputs drive editors.
- Editors: diff highlight on ETag updates; conflict UI when 412/409 occurs (retry flows).
- Selection sync via `AnchorMap`; highlight both panes.

Tools & Planner
- ToolsFactory: register AudioTalk spec in `audiotalk` corpus; verify `GET /tools` list.
- FunctionCaller: path templating + base prefix (done); add simple arg validators (optional).
- Planner: AudioTalk profile with step patterns for screenplay/notation tasks; execution via FunctionCaller.

Ops & DX
- One‑click script: boot AudioTalk, ToolsFactory, FunctionCaller, register tools, run studio.
- ENV guide: `FOUNTAINSTORE_DIR`, `AUDIOTALK_CORPUS_ID`, `FUNCTION_CALLER_BASE_URL`, ports.

Acceptance criteria (polish)
- Chat prompt “change the scene 3 finale to forte and add a rallentando” results in:
  - Updated Fountain tags/notes;
  - Cues mapped;
  - Lily with `\f` and a tempo change block near the correct anchor;
  - Preview updated, events visible in Journal.

Risks & mitigations
- Anchor drift: re‑scan Lily and reconcile anchor map; prefer idempotent IDs from screenplay notes.
- SSE buffering: implement chunked write path in NIO transport; keep message sizes small.
- Planner hallucination: constrain tool set to AudioTalk functions; add tool rejection guardrails.

References
- Specs: `Packages/FountainSpecCuration/openapi/v1/audiotalk.yml`
- Service: `Packages/FountainServiceKit-AudioTalk/`
- Apps: `Packages/FountainApps/Sources/audiotalk-*`, Studio inside `FountainLauncherUI`
- Tools: ToolsFactory (:8011), FunctionCaller (:8004), registration script `Scripts/register-audiotalk-tools.sh`

