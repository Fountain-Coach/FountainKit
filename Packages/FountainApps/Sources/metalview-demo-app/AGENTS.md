# metalview-demo-app — Plan and Operator Notes

Scope
- Demonstrate MetalViewKit as a MIDI 2.0 “instrument” with an operator‑friendly UI.
- Three‑pane layout:
  1) Instrument Map (JSON editor)
  2) MIDI Logs (recent traffic)
  3) Inspector (CI Discover + PE Get/Set) and Transport/Audio

Feature‑Complete Definition
- Visuals: triangle and textured quad render square; depth OK.
- Uniforms: zoom, tint.r/g/b, rotationSpeed (quad), brightness, exposure, contrast, hue, saturation, blurStrength.
- Mapping: NoteOn/CC/PB with shaping (curve, smoothing, quantize, deadband, offset, scale, invert).
- Transports: Loopback + CoreMIDI (network/BLE via system). MIDI‑1 UMP fallback allowed.
- MIDI‑CI: Discovery + PE over SysEx7 UMP (spec messages; chunking), wired to Inspector.
- Logging: channel voice + CI summarized in the middle pane.

MIDI‑CI Identity (Current)
- Manufacturer ID: `0x7D` (developer use). Family/Model: `0x0000/0x0000`. Software rev: `0x00000001`.
- MUID: derived from per‑view `instanceId` (stable per run). Replace IDs when an official Manufacturer ID is assigned.

Developer Checklist
- Keep UI square with `.aspectRatio(1, .fit)` and apply aspect in shaders (x *= height/width).
- Update `MetalInstrument.swift` for CI messages; isolate UMP helpers here.
- Threading: uniform smoothing cache and setUniform must be main‑thread safe.
- Keep header minimal; controls belong inside panes.

Design Source of Truth
- SVG wireframes live under `Design/metalview-demo/`:
  - `wireframe-three-pane.svg` — main layout
  - `wireframe-dual-view.svg` — dual view visual pane
- User story: `Design/MetalViewKit-DEMO-USER-STORY.md`

Run
- `swift run --package-path Packages/FountainApps metalview-demo-app`
- For Wi‑Fi/BLE: enable a CoreMIDI Network session or pair BLE MIDI in Audio MIDI Setup; select destination in the right pane when using CoreMIDI transport.
