FountainApps-SemanticBrowser — Agent Guide

What: This package turns the Semantic Browser service library (`FountainServiceKit-SemanticBrowser`) into a runnable executable (`semantic-browser-server`). Keep it lightweight: process wiring, transport setup, env handling, and a small readiness surface. Specs/configs live in the service kit; do not add generator configs here. FountainStore is the sole persistence backend (defaults to `.fountain/store` unless `SB_STORE_PATH`/`FOUNTAINSTORE_DIR` overrides).

How
- Register generated handlers via `FountainRuntime.NIOOpenAPIServerTransport`; serve with `NIOHTTPServer`.
- Provide a fallback `HTTPKernel` for non‑API endpoints like `/metrics` and `/openapi.yaml`.
- Engine selection envs: `SB_CDP_URL` (CDP), `SB_BROWSER_CLI`/`SB_BROWSER_ARGS` (CLI engine); otherwise use `URLFetchBrowserEngine`.
- Persistence envs: `SB_STORE_PATH` or `FOUNTAINSTORE_DIR` for store root; `SB_STORE_CORPUS`, `SB_PAGES_COLLECTION`, `SB_SEGMENTS_COLLECTION`, `SB_ENTITIES_COLLECTION`, `SB_VISUALS_COLLECTION` for collection names. Index-on-browse respects `index.enabled` in the request payload.
- Static landing: serve `Public/teatro-stage-web/dist` (override with `SB_STAGE_ROOT`) as the default web surface; root `/` returns the stage `index.html` and static assets.
- WebGPU capabilities: `/webgpu/capabilities` returns a JSON manifest (Metal defaults); override path with `SB_WEBGPU_CAPABILITIES_PATH` to serve a custom snapshot for planners/LLMs.

Build/run
- Build: `swift build --package-path Packages/FountainApps-SemanticBrowser -c debug`
- Run: `swift run --package-path Packages/FountainApps-SemanticBrowser semantic-browser-server`
- Helper: `Scripts/semantic-browser [build|run]`

CI
Build this package separately from `FountainApps` to keep CNIO/NIO extras out of unrelated jobs.

Implementation Plan — Atlas-Style Native Host
- Default landing: embed `Public/teatro-stage-web` as the first-load canvas inside the mac app (web view container), preserving three.js + cannon.js scene behavior and baseline viewport math; control the scene via midi2.js events (no CoreMIDI).
- GPU/WebGPU: expose a Swift WebGPU-like façade (device/queue, buffers/textures, encoders, timestamp queries) backed by Metal for now; publish a capability manifest at `/webgpu/capabilities` and wire JavaScriptCore bindings so midi2.js or the stage can target WebGPU-like calls when present, falling back to three.js WebGL when not.
- Control plane: embed midi2.js in JavaScriptCore; provide a loopback MIDI2 transport and adapters mapping UMPs to stage controls, MetalViewKit visuals, and audio bridges; export a MIDI2 capability bitmap so planners stay within timing/payload limits.
- Orchestration: keep Semantic Browser OpenAPI authoritative; route browse/fetch through `semantic-browser-server`, and route timed actions through the MIDI2 scheduler; planner/registry feeds LLM with OpenAPI + MIDI facts + WebGPU capability manifest + stage control schema so plans stay within supported surfaces.
- UI/UX: Atlas-style layout with stage left and a right rail for LLM chat (default to local LLM/ollama), logs, and agent list; include panes for fetched pages (WKWebView), and play/pause/seek for MIDI2-driven stage timelines; “agent browsing” mode streams actions/events into the right rail.
- Observability/tests: add conformance harness for WebGPU façade (triangle/compute/texture upload samples via Swift+JS), smoke tests for server routes, and deterministic replay for MIDI2 sequences; run focused tests with `swift test --package-path Packages/FountainApps-SemanticBrowser`.
- Control bridge status: JSCore midi2 bridge scaffold exists (`Midi2JSBridge`); loads bundle via `SB_MIDI2_BUNDLE` or default vendor paths, exposes `/midi2/status` and `/midi2/schedule` for health/capability probing and UMP injection. Next: wire `scheduleUMP` + capability feed to the stage and planner (`/webgpu/capabilities` + `/midi2/status`).

Root-agent note: allow the Semantic Browser to ship with the embedded `teatro-stage-web` landing scene and JSCore midi2.js bridge (three.js + cannon.js, no CoreMIDI/UIKit; MetalViewKit-only for native GPU work).
