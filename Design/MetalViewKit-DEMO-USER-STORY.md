# MetalViewKit Demo — User Story (Feature-Complete Scope)

Audience
- Creative coders and music producers who want responsive visuals controlled like instruments.
- Goal: drop a Metal view into an app, treat it as a MIDI 2.0 instrument, map controls quickly, and verify behavior via an Inspector.

Primary Narrative
- As an operator, I open the MetalView demo and immediately see a square visual (triangle or textured quad). I can:
  - Toggle Dual View and Link Views to compare and sync two instruments.
  - Enable MIDI and pick a transport (Loopback, CoreMIDI, RTP if needed).
  - Drag across the canvas (Send UMP on drag) to generate velocity; visuals and audio react together.
- I adjust the JSON mapping (left pane) to connect NoteOn/CC/PB to uniform targets (rotationSpeed, zoom, tint.*, brightness, exposure, contrast, hue, saturation, blurStrength), with shaping (curve, smoothing, quantize, deadband, offset, scale, invert).
- I inspect instruments (right pane) via the Inspector:
  - CI Discover Views lists the two per‑view instruments.
  - Press Get to fetch current property snapshot; press Apply to set a modified property set.
  - MIDI Logs (middle pane) reflect CI and Channel Voice traffic.

Jobs-To-Be-Done
- Embed: Use `MetalTriangleView` or `MetalTexturedQuadView` in a SwiftUI/AppKit app, preserve aspect, keep frame cadence stable.
- Play: Drive visuals by MIDI (UMP 2.0 preferred; 1.0 fallback), hear them via the in‑app synth.
- Tune: Iterate on mappings and shaping without recompiling.
- Inspect: Discover instruments, fetch/apply properties (MIDI‑CI), and verify routing.

Acceptance Criteria (Feature‑Complete)
1) Visual correctness
   - Content stays square under resize. Triangle and quad render at 60fps on a typical laptop.
2) Uniforms and mapping
   - Uniforms: zoom, tint.{r,g,b}, rotationSpeed (quad), brightness, exposure, contrast, hue, saturation, blurStrength.
   - JSON mapping applies curve/smoothing/quantize/deadband/offset/scale/invert consistently for NoteOn/CC/PB.
3) MIDI plumbing
   - Loopback, CoreMIDI transports; BLE/Wi‑Fi via CoreMIDI network session works; MIDI‑1 UMP fallback handled.
   - Dual View + Link Views mirrors channel voice to both instruments.
4) MIDI‑CI (spec)
   - Discovery Inquiry/Reply over SysEx7 UMP; Inspector’s Discover populates endpoints.
   - Property Exchange GET/SET envelopes (chunked as needed) for the property model above.
   - CI requests/responses are visible in the log with direction and summary.
5) Inspector ergonomics
   - Three‑pane layout with resizable panes, scrollable editors, and minimal top header.
6) Stability
   - No crashes with rapid mapping edits or MIDI floods; smoothing cache is thread‑safe; instrument endpoints dispose cleanly.

Out‑of‑Scope (v1)
- Per‑note instancing and advanced materials; multi‑texture array binding; persistent profiles.

Risks & Mitigations
- Spec drift: keep CI helpers isolated in `MetalInstrument.swift`; add unit tests for UMP packing/parsing.
- CPU spikes: keep blur simple; guard uniform updates with clamping and EMA smoothing.

Key Success Moments
- “I turned a knob and the quad breathes like a filter.”
- “Inspector showed me properties and I set them — no code change.”
- “Two instruments respond in lockstep when linked; CoreMIDI network just works.”

