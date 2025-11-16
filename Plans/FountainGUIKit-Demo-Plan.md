## FountainGUIKit Demo Integration Plan

### Context — Why This Demo Lives in FountainKit
FountainGUIKit is a standalone GUI framework that gives us an NSView‑based host, a pure‑Swift node graph, and a full gesture event model without depending on SwiftUI or CoreMIDI. This plan covers how we adopt that framework inside FountainKit as a first‑class demo: a small, instrument‑centric surface that exercises gestures, MIDI 2.0 CI/PE, and robot testing from day one.

### Goals
- Embed a FountainGUIKit‑backed NSView surface in the FountainKit workspace as a minimal, fast‑building demo app.
- Prove end‑to‑end gesture coverage (scroll, drag, magnify/pinch, rotate, swipe) mapped into a stable property schema.
- Keep the demo CoreMIDI‑free, using the existing MIDI 2.0 transports and CI/PE machinery only.
- Make the demo robot‑testable via MRTS and PB‑VRT, aligned with the Baseline‑PatchBay invariants.
- Treat AGENTS and PLAN docs as the authoritative description of the demo’s behaviour; implementation follows.

### Phase 1 — Dependency and Build Wiring
- Add a SwiftPM dependency on `FountainGUIKit` to `Packages/FountainApps/Package.swift` using the GitHub URL under the Fountain Coach org.
- Introduce a `fountain-gui-demo` executable target in `Packages/FountainApps` that depends on the `FountainGUIKit` library product only (no additional services).
- Follow the service‑minimal pattern:
  - Add `Scripts/dev/fountain-gui-demo-min` that exports `FK_SKIP_NOISY_TARGETS=1` and builds/runs only the `fountain-gui-demo` target.
  - Ensure `FOUNTAIN_SKIP_LAUNCHER_SIG=1` is honoured so the demo compiles quickly and stays isolated from the full launcher stack.
- Verify `swift build --package-path Packages/FountainApps -c debug --target fountain-gui-demo` succeeds on a clean checkout.

### Phase 2 — NSView Host Demo (No Metal Yet)
- Implement the `fountain-gui-demo` main as a small AppKit app:
  - Create an `NSApplication` + `NSWindow` pair with a single `FGKRootView` as `contentView`.
  - Instantiate a root `FGKNode` that spans the window, with an attached `FGKEventTarget` that logs all `FGKEvent` cases for manual inspection.
  - Ensure the demo runs without Metal or MIDI; at this phase it is purely an event/gesture playground.
- Add `Scripts/apps/fountain-gui-demo` as a thin wrapper that:
  - Optionally seeds configuration (if needed later).
  - Invokes `swift run --package-path Packages/FountainApps fountain-gui-demo` or the `fountain-gui-demo-min` helper.
- Document the demo entry points and expected behaviour in the relevant FountainApps AGENTS file and in `Scripts/AGENTS.md`.

### Phase 3 — Gesture Semantics and Property Schema
- Define a minimal property schema for the demo surface using `FGKPropertyDescriptor` on the root node, aligned with Baseline‑PatchBay where possible:
  - `canvas.zoom` (float) driven by magnify/pinch gestures.
  - `canvas.translation.x` and `canvas.translation.y` (float) driven by scroll/drag.
  - Optional extras (e.g., `canvas.rotation`, `canvas.reset`) for rotate gestures and keyboard shortcuts.
- Implement an `FGKEventTarget & FGKPropertyConsumer` for the root node that:
  - Interprets FGK gesture events into property changes.
  - Emits property changes through a single internal API so MIDI 2.0 integration and robot scripts can share semantics.
- Update FountainApps‑scoped AGENTS docs to describe:
  - How each gesture maps to each property.
  - Expected invariants (e.g., anchor‑stable zoom, pan behaviour) without embedding Teatro prompts themselves.

### Phase 4 — MIDI 2.0 CI/PE Integration (CoreMIDI‑Free)
- Use existing FountainTelemetryKit MIDI 2.0 transports to expose the demo’s property schema via Property Exchange:
  - Treat the root node as a MIDI 2.0 instrument with a stable `instrumentId`.
  - Map properties (`canvas.zoom`, `canvas.translation.{x,y}`, etc.) into CI/PE facts using the OpenAPI‑to‑facts tooling where appropriate.
- Add a small adapter that:
  - Bridges property changes from the FGK layer into MIDI 2.0 CI/PE messages.
  - Listens for CI/PE SET operations and forwards them back into `setProperty(_ name:value:)` on the node graph.
- Confirm that all of this uses the existing `MIDI2`/`MIDI2Transports` stack only; the demo must never import CoreMIDI.

### Phase 5 — MRTS and PB‑VRT Alignment
- Introduce a new MRTS suite for the demo under `Packages/FountainApps/Tests`, following the patterns used for Baseline‑PatchBay:
  - Drive the demo exclusively via MIDI 2.0 CI/PE using the instrument’s property schema.
  - Assert numeric invariants for zoom, pan, rotation, and reset behaviour.
- Wire the demo into PB‑VRT visual regression testing:
  - Add snapshots of the demo surface at key zoom/pan states.
  - Ensure PB‑VRT harnesses can target the `fountain-gui-demo` app via the same scripting interface used for existing PatchBay tests.
- Align robot and PB‑VRT docs in `Plans/Robot-Testing.md` and relevant AGENTS files so the demo’s coverage is visible and maintained.

### Phase 6 — Documentation, Prompts, and Operator Ergonomics
- Add or extend an AGENTS file under the `fountain-gui-demo` source directory to:
  - Describe the demo’s purpose, gesture semantics, property schema, and MIDI 2.0 wiring.
  - Declare how it participates in MRTS and PB‑VRT (which tests, scripts, and prompts apply).
- Add a short demo section to the FountainApps README (or a dedicated demo README) that:
  - Shows how to run the demo via `Scripts/dev/fountain-gui-demo-min` or `Scripts/apps/fountain-gui-demo`.
  - Points to the AGENTS file and this plan as canonical references.
- Follow the FountainStore prompt policy:
  - Seed any Teatro prompts and facts for the demo via a dedicated `*-seed` executable and `Scripts/apps` wrapper.
  - Never embed prompt text or facts in this plan or in code; always reference the `prompt:<app-id>` page in FountainStore instead.

### Definition of Done
- `fountain-gui-demo` builds and runs via targeted scripts, with FountainGUIKit providing the NSView host and event model.
- All primary gestures (scroll, drag, magnify/pinch, rotate, swipe) are wired into a documented property schema, with behaviour matching the design intent.
- MIDI 2.0 CI/PE integration is in place and CoreMIDI is not referenced anywhere in the demo codepath.
- MRTS and PB‑VRT suites cover the demo’s key interactions and visual states, with passing tests in CI.
- AGENTS, this plan, and operator‑facing docs stay in sync whenever the demo’s behaviour or surface changes.

