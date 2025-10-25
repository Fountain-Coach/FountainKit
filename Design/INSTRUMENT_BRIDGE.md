# Fountain Instrument Bridge — MIDI 2.0 Sampler + ML + AudioTalk

Status: draft (intentional), current build is usable today

## Executive Summary

MIDI 1.0 samplers were powerful but brittle to configure. Mapping knobs to CCs, banking programs, and achieving consistent per-note expressivity usually required DAW templates, vendor tools, or hacks like Autosampler to “freeze” sounds. 

Fountain’s Instrument Bridge modernizes that experience with three pillars:

- MIDI 2.0 everywhere: true per-note expressivity, 32‑bit velocity, high‑resolution pitch, and — crucially — MIDI‑CI Discovery + Property Exchange for self‑describing instruments.
- In‑process sampler and visual instruments: a sampler DSP engine (midi2sampler) and Metal‑based visual instruments that both present as MIDI 2.0 devices with discoverable properties.
- ML/audio pipelines that emit MIDI 2.0: real‑time pitch/poly inference or DSP estimates feeding UMP NoteOn/PE streams, optionally rendering locally in‑process for instant feedback.

Together this removes guesswork. Devices introduce themselves, publish their properties, and can be configured programmatically. Audio and ML tools speak the same language (MIDI 2.0 UMP) and can drive in‑app or external sound generators deterministically.

## What We Built

### Components

- MIDI 2.0 stack
  - Transports via CoreMIDI (virtual endpoints + optional RTP/Network sessions).
  - MIDI‑CI scaffolding: Discovery Inquiry/Reply and Property Exchange (PE). Current replies include a developer manufacturer ID (0x7D) and a JSON property snapshot; full CI envelopes (transactions/chunking) are on the roadmap.

- Sampler (Midi2SamplerDSP)
  - Integrated as an SPM package (tag v0.1.1), exposing a real‑time note processor and DSP helpers (DC removal, crossfades, RMS, morphing).
  - Local render bridge (`SamplerSynth`) drives the processor in‑process while still sending MIDI 2.0 events — low‑latency feedback without external setup.

- Visual instruments (MetalViewKit)
  - `MetalTriangleView` and `MetalTexturedQuadView` are MIDI 2.0 “instruments” with per‑view virtual endpoints.
  - Uniforms (rotation, zoom, tint, etc.) map to Channel Voice events; Property Exchange advertises identity and tunables.

- ML + Audio runners
  - `ml‑audio2midi`: mic/file → monophonic pitch (DSP f0 fallback) → MIDI 2.0 NoteOn + high‑resolution PB; optional local render.
  - `ml‑basicpitch2midi`: file → poly activations (spectral fallback) → MIDI 2.0 NoteOn/Off; optional local render.
  - CoreMLKit and MetalComputeKit provide a path to GPU/ML acceleration (MPSGraph, vDSP), with fast smoke tests and capability detection.

- AudioTalk interface
  - AudioTalk is the service lane to present a stable API for these instruments and pipelines. With the Bridge, AudioTalk can query instruments via MIDI‑CI, set properties, route UMP streams, and surface health/diagnostics.

### Why This Is Different (vs. MIDI 1.0)

- Discoverability: MIDI‑CI Discovery and Property Exchange allow instruments to describe themselves. Hosts can fetch a property schema instead of guessing CCs.
- Precision + expressivity: 32‑bit velocity, 16‑bit PB, per‑note controllers enable nuanced mapping without stepping or zipper noise.
- Determinism: Property snapshots (JSON), ETags, and journaled actions make sessions reproducible across machines.
- In‑app render: The sampler can run in the same process as the controller, enabling instant feedback loops without driver dance.

## How It Fits Together (Architecture)

```
[Audio/Mic or File] ──▶ [ML / DSP (CoreMLKit or DSP fallback)] ──▶ [MIDI 2.0 UMP]
                                                    │
                                                    ├──▶ [Local Render (SamplerSynth → Midi2SamplerDSP)]
                                                    │
                                                    └──▶ [External Destinations (DAW / Hardware / Network)]

           ▲                                                       │
           │                                                       ▼
  [MIDI‑CI Discovery + Property Exchange] ◀────── [AudioTalk / Host API]
```

Key flows:
- ML/DSP emits UMP NoteOn/Off/PB/CC events. The same stream can feed local render and external targets.
- Instruments (sampler or visual) publish properties via CI (identity, tunables) and accept PE set/get.
- AudioTalk coordinates: device selection, routing, property snapshots, and health.

## What We Implemented (Concrete)

- Midi2SamplerDSP integration
  - Pinned to GitHub (v0.1.1). Fixed DSP math (sqrtf), added DCMode, trimmed target to real‑time modules.
  - `SamplerSynth` bridges AVAudioEngine → RealTimeNoteProcessor; optional DC removal and block processing.

- MIDI‑CI scaffolding
  - Instruments and runners reply to Discovery Inquiry (with a developer manufacturer ID 0x7D) and publish a vendor JSON property snapshot. Full CI transactions/chunking are staged.

- Visual instruments (MetalViewKit)
  - Per‑view virtual endpoints; Channel Voice → uniforms mapping; CI vendor JSON snapshot for identity/tunables.
  - Aspect‑ratio fixes and uniform sets for realistic control.

- ML/audio runners
  - `ml‑audio2midi` (monophonic) and `ml‑basicpitch2midi` (poly) both support `--render` to hear results immediately.
  - Fallback DSP paths ensure a demo works even without Core ML models on disk; CoreMLKit supports model loading when present.

- Tooling + CI
  - `Scripts/audio/tonegen.sh` generates WAVs (sine/square/saw/triangle/noise/chirps/chords).
  - GitHub Actions “ML Bridge Smoke” builds runners and runs compute tests on macOS runners.

## Developer Experience

Quick listen (local render):

```
# Generate a tone
bash Scripts/audio/tonegen.sh --type sine --freq 440 --dur 1

# Monophonic pitch → MIDI 2.0 → local sampler render
swift run --package-path Packages/FountainApps ml-audio2midi \
  --file Public/Audio/sine_440_1s.wav --render --publish-map

# Poly fallback path
swift run --package-path Packages/FountainApps ml-basicpitch2midi \
  --file Public/Audio/sine_440_1s.wav --render --publish-map

# Simple in‑process synth demo
swift run --package-path Packages/FountainApps ml-sampler-smoke --pattern arp --wave triangle --duration 4
```

## What’s Next

- Full MIDI‑CI compliance
  - Discovery Inquiry/Reply: complete manufacturer/family/model codes, MUIDs, function blocks, max SysEx, and CI version fields.
  - Property Exchange: transaction IDs, chunking, and schema‑based GET/SET for sampler programs and parameters.

- Rich property schema
  - Standardize identity + parameter schema across sampler and visual instruments; publish via CI; persist snapshots with ETags.

- ML model upgrades
  - Swap DSP fallbacks for Core ML models (CREPE/YAMNet/BasicPitch). Provide deterministic fixtures and gating tests.

- AudioTalk as the control plane
  - Expose a clean HTTP/OpenAPI surface to list instruments, fetch CI snapshots, set properties, and route streams.

## Why This Matters

This bridge replaces “mystery mapping” with self‑describing instruments and a reproducible control plane. It collapses setup time, unifies audio, ML, and graphics under MIDI 2.0 semantics, and makes sophisticated, expressive control attainable without vendor lock‑ins or DAW‑specific templates.

It is a practical on‑ramp to a future where samplers and visual instruments are discoverable, configurable, and verifiable — by code and by humans.

