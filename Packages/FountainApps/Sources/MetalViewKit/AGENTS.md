# MetalViewKit — Agent Guide

MetalViewKit provides embeddable Metal views for macOS (SwiftUI/AppKit) with a stable renderer API. It’s MIDI‑friendly by design: uniform names are clear, frame behavior is predictable, and each view can optionally run in a MIDI 2.0 “instrument mode” without coupling the renderer to any transport.

In instrument mode, a view owns a unique instrument identity (manufacturer, product, instance GUID) surfaced via MIDI‑CI Discovery and CoreMIDI endpoint names (e.g. `MetalTriangleView#A1B2`). Enabling the mode creates per‑instance virtual endpoints — a destination for incoming UMP and a source for replies/telemetry — using the MIDI 2.0 protocol (legacy peers see bridged 1.0 via CoreMIDI where needed). The view advertises a JSON property schema (initially `rotationSpeed`, `zoom`, and `tint.r/g/b`) and speaks a minimal vendor JSON for GET/SET snapshots. Future work moves to spec‑accurate MIDI‑CI PE with chunking.

MetalViewKit exposes a small facilitator for apps to toggle per‑view endpoints or route UMP manually. The `MetalSceneRenderer` remains transport‑agnostic; UMP decode sits in a helper alongside each renderer. Planned types include `MetalInstrumentDescriptor` (identity and endpoint names) and a `MetalInstrument` runtime (enable/disable, `receiveUMP(_:)`, PE handlers, and `publishState()` when properties change). Views get an init knob like `instrument: MetalInstrumentDescriptor? = nil`.

Everything is an Instrument: in MetalViewKit land, every entity (canvas, node, inspector) can operate in “instrument mode” and expose a MIDI‑CI identity + optional Property Exchange (PE). Keep rendering transport‑agnostic; instrument mode is additive and optional. Use stable endpoint names like `<product>#<instanceId>`.

Property schema example:
```
{
  "version": 1,
  "properties": [
    {"name":"rotationSpeed","type":"float","min":0.0,"max":4.0,"default":0.35},
    {"name":"zoom","type":"float","min":0.2,"max":4.0,"default":1.0},
    {"name":"tint.r","type":"float","min":0.0,"max":1.0,"default":1.0},
    {"name":"tint.g","type":"float","min":0.0,"max":1.0,"default":1.0},
    {"name":"tint.b","type":"float","min":0.0,"max":1.0,"default":1.0}
  ]
}
```

Transport notes: CoreMIDI endpoints are per‑view when instrument mode is enabled. Apps without CoreMIDI still use the renderer and call `setUniform`; instrument mode is optional. RTP/Network MIDI remains app‑level; to run true 2.0 end‑to‑end, forward UMP to a peer and let each view consume it.

MIDI‑CI identity defaults use 0x7D (developer) as Manufacturer ID, placeholder Family/Model, and a software revision of `0x00000001`. MUID is derived from `instanceId` (hashed to 28‑bit) and stays stable per instance. Update `MetalInstrument.sendDiscoveryReply()` with your assigned ID when available.

Public API
- Views: `MetalTriangleView(onReady:)`, `MetalTexturedQuadView(rotationSpeed:onReady:)`
- Renderer handle: `onReady: (MetalSceneRenderer) -> Void` yields the renderer
- Renderer methods: `setUniform(_ name: String, float: Float)`, `noteOn`, `controlChange`, `pitchBend`

Uniforms
- Common: aspect correction in the vertex shader keeps content square in non‑square viewports
- Triangle: `zoom`; `tint.r/g/b`; `brightness`, `exposure`, `contrast`, `hue`, `saturation`
- Textured Quad: `rotationSpeed`, `zoom`; `tint.r/g/b`; `brightness`, `exposure`, `contrast`, `hue`, `saturation`, `blurStrength`
- Accepted names: `rotationSpeed` (quad), `zoom`, `tint[.r/.g/.b]`, `brightness`, `exposure`, `contrast`, `hue`, `saturation`, `blurStrength`

Shader and performance
Inline MSL is compiled via `device.makeLibrary(source:)` to avoid metallib drift. The quad binds uniforms to vertex `buffer(1)` and fragment `buffer(0)` — keep indices aligned. Maintain 16‑byte struct alignment; group floats to `float4` as you expand. Double‑buffer uniforms if stalls appear under load; keep total uniforms reasonable (≤64 floats); avoid shared mutable state in the render loop (confine to the MTKView delegate thread).

Adding uniforms
Add backing vars in Swift, update `setUniform`, and resize the uniform buffer; mirror changes in MSL and keep buffer indices aligned. Update usage docs and demo mapping targets as needed.

Mapping integration
The renderer stays transport‑agnostic; the demo parses JSON mapping and calls `setUniform`. In instrument mode, the same properties are discoverable and settable via PE — no hard‑coded CCs.

Canvas Nodes (draft)
- Nodes conform to a MetalCanvasNode protocol (doc-space `frameDoc`, port geometry provider, Metal encode method). The canvas owns pan/zoom and passes an `MTKView`/`MTLCommandBuffer` to each node to render its body in the same pass as its ports/wires.
- Stage nodes will implement `node = page` by drawing the page body and placing input ports at baseline midpoints; panel/query/transform nodes keep tile bodies.
- No overlays: HUD (ticks/selection) remains transient; node bodies are rendered by the node itself.

MIDI Robot Testing (canonical) — Default Policy
Narrative first: we test every interactive surface by treating it as a MIDI 2.0 instrument and by validating invariants against the canonical 2D transform. No UI automation is needed — tests send UMP and observe deterministic transform updates.

Why
- Driving via MIDI makes tests transport‑agnostic and production‑faithful. The canvas, nodes, and inspectors remain consistent regardless of the UI toolkit.

Default
- Every MetalViewKit view is “midified” by default. If an app does not pass an explicit descriptor, the view creates its own instrument (`manufacturer: Fountain, product: Canvas, displayName: Canvas`).

What
- Robot: a CoreMIDI sender emitting MIDI‑CI PE SET as SysEx7 UMP (JSON). Properties include `zoom`, `translation.x` and `translation.y` (expand per instrument).
- Invariants: follow‑finger pan (`docDelta = viewDelta/zoom`, correct sign) and anchor‑stable zoom (doc point under anchor remains within ≤1 px in view).
- Evidence: UMPRecorder writes `.ndjson` under `.fountain/corpus/ump`. Knowledge harvester writes `knowledge‑latest.json` for quick indexing. Replay exporters reconstruct visuals event‑by‑event for movies/frames.

How
- Renderer posts notifications: `MetalCanvasRendererReady` (for test attach) and `MetalCanvasTransformChanged` (for verification).
- Tests send PE SET `{properties:[{"name":"translation.x","value":…}, …]}` to the canvas virtual destination (e.g., “PatchBay Canvas”), then assert transform invariants.
- Log‑driven tests load the newest `stream-*.ndjson` and apply `ui.pan/ui.zoom` to a `Canvas2D` instance, asserting invariants and exporting failure artifacts via replay.

Where
- Robot + tests live under `Packages/FountainApps/Tests/PatchBayAppUITests/`.
- Renderer hooks live in `MetalCanvasView.swift`.
- Knowledge harvester: `patchbay-app/Monitor/KnowledgeAuto.swift` (auto‑harvest on launch).

Baseline default
- The default UI baseline is Baseline‑PatchBay (grid‑dev‑app). Any change to baseline viewport math must be paired with an MRTS Teatro prompt and matching robot tests. Baseline prints both prompts on boot (creation + MRTS). See `Scripts/ci/baseline-robot.sh` for the invariants subset and `baseline-robot-seed` for persisting the MRTS prompt.

Maintenance
- Keep property names stable (PE schema in lockstep with renderer). Extend via additive properties. Update tests and docs together when invariants evolve. Apps should assume instruments exist and are robot‑testable by default.

Testing
Build and run: use the robot tests to set exact transforms; rely on replay tests for end‑to‑end validation. Keep “Monitor” enabled to mirror outgoing events.

Change control
Maintain source compatibility on public uniform names. If a rename is required, support both names (alias) until callers migrate.
