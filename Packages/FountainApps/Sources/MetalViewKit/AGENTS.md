# MetalViewKit — Agent Guide

Path: `Packages/FountainApps/Sources/MetalViewKit/**`

## Contents
- Overview
- MIDI 2.0 Instrument Mode
  - Goals
  - Identity & Discovery
  - Endpoints
  - Property Exchange (PE)
  - Profiles
  - UMP Channel Voice
  - App Integration
  - Planned API
  - Property Schema
  - Transport Notes
- Public API
- Uniforms
  - Accepted names
- Shader & Performance
  - Guidance
- Adding New Uniforms
- Mapping Integration
- Testing
- Change Control

## Overview
- Embeddable Metal views for macOS (SwiftUI/AppKit) with a stable renderer API.
- MIDI‑friendly: clear uniform names; predictable frame behavior; optional MIDI 2.0 instrument mode per view.

## MIDI 2.0 Instrument Mode

### Goals
Each MetalViewKit view can run as a MIDI 2.0 instrument with discovery and Property Exchange (optional), while keeping the renderer transport‑agnostic.

### Identity & Discovery
- Each instance owns a unique instrument identity (manufacturer, product, instance GUID) exposed via MIDI‑CI Discovery and CoreMIDI endpoint names.
- Endpoint names include the view type and a short instance id (e.g., `MetalTriangleView#A1B2`).

### Endpoints
- When enabled, a view creates per‑instance CoreMIDI virtual endpoints:
  - Destination: receives UMP
  - Source: publishes replies/telemetry
- Endpoints are created with MIDI 2.0 protocol. Legacy peers see bridged MIDI 1.0 behavior via CoreMIDI when necessary.

### Property Exchange (PE)
- The view advertises a JSON schema describing its controllable properties (initial: `rotationSpeed`, `zoom`, `tint.r/g/b`).
- Minimal vendor JSON (current):
  - GET → `{}` request; reply with snapshot
  - SET → `{ "properties": [{"name":"zoom","value":1.25}, ...] }`; apply + snapshot reply
- Future: spec‑accurate MIDI‑CI PE (Discovery Inquiry/Reply, GET/SET with chunking).

### Profiles
- Optional vendor profile to group related capabilities; standard profiles may be added later.

### UMP Channel Voice
- NoteOn/Off/CC/PB supported; the instrument also responds to MIDI‑CI utility/PE messages.

### App Integration
- MetalViewKit exposes a small facilitator; apps can enable per‑view endpoints or route UMP manually.
- The `MetalSceneRenderer` remains transport‑agnostic; UMP decode stays in a helper layered alongside each renderer.

### Planned API
- `MetalInstrumentDescriptor`: identity (manufacturer/product/instanceId), endpoint names, group/channel masks.
- `MetalInstrument` runtime:
  - `enable()` / `disable()` lifecycle
  - `receiveUMP(_:)` and PE handlers (GET/SET of property JSON)
  - `publishState()` to emit PE snapshots/telemetry when properties change
- View init knob: `instrument: MetalInstrumentDescriptor? = nil` (nil = disabled)

### Property Schema
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

### Transport Notes
- CoreMIDI virtual endpoints are per‑view when instrument mode is enabled.
- Apps without CoreMIDI can still use the renderer and call `setUniform`; instrument mode is optional.
- RTP/Network MIDI remains app‑level; for true 2.0 over network between two apps, forward UMP to the peer and let each view consume it.

### MIDI‑CI Identity (Current)
- Manufacturer ID: `0x7D` (developer use). This is intentional for development; replace with your assigned ID when available.
- Device Family/Model: `0x0000/0x0000` (placeholder).
- Software Revision: `0x00000001` (bump as needed).
- MUID: derived from the view’s `instanceId` (hashed to 28‑bit). Stable per instance; regenerated per run when `instanceId` changes.
- Property Exchange: JSON encoding, supports `GET`/`SET` (transactioned) and capability inquiry.

Buy‑in (later)
- When you obtain an official Manufacturer ID, update the constants in `MetalInstrument.sendDiscoveryReply()` and, if applicable, set real Family/Model codes. No other code changes required.

## Public API
- Views
  - `MetalTriangleView(onReady:)`
  - `MetalTexturedQuadView(rotationSpeed:onReady:)`
- Renderer handle
  - `onReady: (MetalSceneRenderer) -> Void` exposes the renderer.
  - `MetalSceneRenderer` methods:
    - `setUniform(_ name: String, float: Float)`
    - `noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8)`
    - `controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8)`
    - `pitchBend(value14: UInt16, channel: UInt8, group: UInt8)`

## Uniforms
- Common
  - Aspect correction in vertex shader keeps content square for non‑square viewports.
- Triangle
  - `zoom` (Float): uniform scale.
  - `tint.r`, `tint.g`, `tint.b` (0…1): color multiplier.
  - `brightness` (Float −1…1), `exposure` (stops), `contrast` (0.5…2), `hue` (radians), `saturation` (0…2)
- Textured Quad
  - `rotationSpeed` (Float): radians/sec rotation.
  - `zoom` (Float): uniform scale.
  - `tint.r`, `tint.g`, `tint.b` (0…1): color multiplier.
  - `brightness`, `exposure`, `contrast`, `hue`, `saturation`, `blurStrength` (0…1)

### Accepted names
- `rotationSpeed` (quad only)
- `zoom`
- `tint` or `tint.r`, `tint.g`, `tint.b`
- `brightness`, `exposure`, `contrast`, `hue`, `saturation`, `blurStrength`

## Shader & Performance
- Inline MSL compiled via `device.makeLibrary(source:)` to avoid metallib drift.
- Quad binds uniforms to vertex `buffer(1)` and fragment `buffer(0)` — keep indices aligned.
- Maintain 16‑byte struct alignment; group floats to `float4` when expanding.

### Guidance
- Double‑buffer uniforms if stalls appear under load.
- Keep total uniforms reasonable (≤64 floats).
- Avoid shared mutable state in render loops; renderers are confined to the MTKView delegate thread.

## Adding New Uniforms
1) Swift: add backing vars, update `setUniform`, and resize the uniform buffer.
2) MSL: extend the uniform struct and usage; keep buffer indices aligned.
3) Docs: update usage and demo mapping targets as needed.

## Mapping Integration
- Transport‑agnostic: only `MetalSceneRenderer` is exposed.
- Demo app parses JSON mapping and calls `setUniform` on the renderer.
- In instrument mode, the same properties are available via PE for discovery/setting without hardcoded CCs.

## Testing
- Build the demo and verify:
  - Triangle: tint/zoom via UI or MIDI CC.
  - Quad: rotationSpeed/tint/zoom via mappings.
- Keep “Monitor” enabled to mirror outgoing events for debugging.

## Change Control
- Maintain source compatibility on public uniform names.
- If renaming is necessary, support both names (alias) until call sites migrate.
