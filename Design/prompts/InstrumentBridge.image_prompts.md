## Image Prompts — Instrument Bridge

Guidelines
- Style: clean, schematic, readable on dark or light backgrounds.
- Palette: neutral grays + accent Fountain blue (#2F74FF) and teal (#00B3A4).
- Format: SVG 1200×700 (landscape) with legible text at 100%.
- Fonts: system sans (e.g., SF Pro / Inter) or outline shapes; avoid tiny labels.

1) instrument-bridge-architecture.svg
- Title: Instrument Bridge — Architecture
- Nodes (left→right):
  - Audio/Mic or File
  - ML/DSP Inference (CREPE/BasicPitch or DSP f0)
  - MIDI 2.0 UMP Stream
  - Local Render (SamplerSynth → Midi2SamplerDSP)
  - External Destinations (DAW / Hardware / Network)
  - AudioTalk Control Plane (above), arrows down to ML/DSP and Instruments
- Arrows:
  - Audio → ML/DSP → UMP → (split) → Local Render and External Destinations
  - AudioTalk (top) has control arrows to ML/DSP (parameters) and to Instruments (CI/PE)
- Badges:
  - UMP node shows NoteOn/Off, PB, CC, PE
  - CI bubble near Instruments: Discovery + Property Exchange

Prompt:
“Create a clean architecture diagram showing Audio input feeding ML/DSP, producing a MIDI 2.0 UMP stream that splits to a Local Sampler Render and External Destinations, with an AudioTalk Control Plane managing CI/PE above. Use SVG 1200×700, neutral grays, accent #2F74FF/#00B3A4, clear node labels, and directional arrows.”

2) ci-property-exchange-flow.svg
- Title: MIDI‑CI — Discovery + Property Exchange
- Swim lanes: Host (AudioTalk/DAW) vs. Instrument (Sampler/Visual)
- Exchanges:
  - Discovery Inquiry → Discovery Reply (MUIDs, functions, maxSysEx)
  - PE GET (schema or snapshot) → PE GET Reply
  - PE SET (properties) → PE Set Reply/ACK
- Notes:
  - Dev Manufacturer ID 0x7D used now; full CI chunking/transactions on roadmap

Prompt:
“Draw a two-lane sequence diagram (Host vs Instrument) for MIDI‑CI Discovery Inquiry/Reply and Property Exchange GET/SET flows. Include callouts for MUIDs, functions, maxSysEx, and a note that dev manufacturer ID 0x7D is used. SVG 1200×700.”

3) ml-audio2midi-pipeline.svg
- Title: Audio → MIDI 2.0 Pipeline
- Steps: Audio/Mic → Feature Extraction → Pitch/Activation → Event Builder → UMP Output
- Options:
  - CREPE/BasicPitch if present, otherwise DSP fallback
  - PB 16‑bit, Velocity 32‑bit, per‑note channels

Prompt:
“Create a pipeline diagram from Audio/Mic through Feature Extraction and Pitch/Activation into a MIDI 2.0 Event Builder, producing UMP NoteOn/Off + high resolution PB/Velocity. Indicate CoreML models (CREPE/BasicPitch) vs DSP fallback. SVG 1200×700.”

4) visual-instrument-mapping.svg
- Title: Visual Instruments — Mapping
- Elements:
  - Per‑view MIDI 2.0 Endpoint (MetalTriangle/MetalTexturedQuad)
  - Mapping table callout: rotationSpeed ↔ NoteOn 60, zoom ↔ CC2, tint.r/g/b ↔ CC20/21/22
  - Uniform buffer block visualization

Prompt:
“Design a diagram of a Visual Instrument (Metal view) exposing a per‑view MIDI 2.0 endpoint. Show Channel Voice mappings (rotationSpeed→Note 60, zoom→CC2, tint r/g/b→CC20/21/22) feeding a Uniform buffer, which drives the renderer. SVG 1200×700.”

5) audiotalk-control-plane.svg
- Title: AudioTalk — Control Plane
- Areas:
  - Device list (Endpoints)
  - CI Snapshot (identity/properties)
  - Routing (UMP paths)
  - Health/Logs
  - Actions: GET/SET properties, start/stop

Prompt:
“Sketch an interface block diagram for AudioTalk as a control plane: device list, CI snapshots (identity/properties), routing (UMP paths), health/logs, and actions (GET/SET, start/stop). SVG 1200×700.”

