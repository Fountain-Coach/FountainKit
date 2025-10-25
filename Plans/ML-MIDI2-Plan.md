# ML × MIDI 2.0 — Working Plan

## Purpose
- Deliver spec-accurate, discoverable, and low-latency ML-driven audio pipelines that produce expressive MIDI 2.0 streams and vendor properties discoverable via MIDI-CI.
- Keep scope modular: CoreMLKit (models), CLI runners (pitch/poly/scenes), MetalViewKit (visuals), and Teatro (audio) wired together through CoreMIDI/MIDI 2.0.

## Scope
- Runners: `ml-audio2midi` (pitch), `ml-basicpitch2midi` (poly), `ml-yamnet2midi` (scenes).
- CoreMLKit: model load/compile/predict; fetch/convert tooling; audio/vision helpers.
- MIDI 2.0: CoreMIDI transport, MIDI-CI Discovery + Property Exchange (PE), vendor JSON fallback, CI-framed SysEx7 envelopes.
- Integration: MetalViewKit (visuals) and Teatro synth (audio) in the same app or routed via CoreMIDI.

Non-goals (for now)
- Training models from scratch.
- Bundling large model artifacts in the repo.
- Cross-platform beyond macOS 14+.

## Deliverables
- Executables
  - `ml-audio2midi` (pitch → NoteOn + 32-bit PB; mic/file; PE snapshot)
  - `ml-basicpitch2midi` (poly → NoteOn/Off; mic/file; PE snapshot)
  - `ml-yamnet2midi` (scene → Program Change + mapping; PE snapshot)
- Tooling
  - `coreml-fetch` (SqueezeNet, YAMNet + labels, URL fetch, notes)
  - `Scripts/apps/coreml-convert.sh` + `coreml_convert.py` (CREPE/BasicPitch/Keras/TFLite → .mlmodel)
- Examples
  - `Public/Models/pitch_props.example.json`
  - `Public/Models/poly_props.example.json`
  - `Public/Models/yamnet_program_map.example.json`
- Docs
  - `Packages/FountainApps/Sources/CoreMLKit/AGENTS.md` (usage, fetch/convert, demos)

## Milestones
1) M1 Spec-Correct CI/PE (runners + views)
   - Full MIDI-CI Discovery Reply (MUID, function blocks, manufacturer 0x7D dev, maxSysEx) and Profile Inquiry handling.
   - PE GET/SET with transaction IDs + chunking; unify property schema across pitch/poly/scenes.
2) M2 Model Pathing (fetch/convert)
   - One-command fetch/convert for CREPE‑tiny + BasicPitch (auto placement under `Public/Models`).
   - Pre/post pipelines: framing/normalization/mel as required per model.
3) M3 Integration Demo
   - Single app driving Teatro synth + MetalViewKit visuals in sync; publish combined instrument PE snapshot.
   - Scene mapping drives program/property sets end-to-end.
4) M4 Performance + Diagnostics
   - Lock-free audio ring buffer, JR Timestamps, latency logging, CoreMIDI Network/RTP interoperability report.
5) M5 Test/CI Coverage
   - File-based deterministic smokes for each runner; CI job executes only the runners; PE round-trip tests; latency sanity.

## Workstreams
 - MIDI2 Instrument Bridge (midi2sampler)
  - Goal: use midi2sampler as the in‑process audio engine for low‑latency playback driven by our MIDI 2.0 UMP streams.
  - Integration options:
    - Preferred: add as SPM dependency by URL (`.package(url: "https://github.com/Fountain-Coach/midi2sampler.git", branch: "main")`) and depend on its library product (e.g., `MIDI2Sampler`).
    - Alternate: add as a git submodule under `External/midi2sampler` and reference with a `.package(path: "../../External/midi2sampler")` (mirrors how `TeatroFull` is integrated).
  - Adapter: implement `SamplerSynthDevice: SynthDevice` (matching `Packages/FountainApps/Sources/metalview-demo-app/SynthDevice.swift`) behind `#if canImport(MIDI2Sampler)` to keep builds green when absent.
  - Routing: add a `--render` flag to the CLI runners to route local UMP to the in‑process sampler in addition to CoreMIDI endpoints.
  - Property Exchange: publish sampler banks/programs/parameters via CI vendor JSON (and then full PE envelopes) and respond to GET/SET for program changes, gain, ADSR, filter.
  - Smoke: add `ml-sampler-smoke` to load a preset and emit a short pattern to verify audio starts; a file render variant for CI (noninteractive).
  - Docs: update CoreMLKit AGENTS to include sampler wiring; note feature toggles and bank/program expectations.
- CI/PE Envelope (Spec)
  - Implement Discovery/PE helpers shared by all runners and MetalViewKit instruments.
  - Replace vendor JSON shims with spec envelopes (keep JSON as the PE payload body for now).
- Models & Pre/Post
  - CREPE‑tiny, BasicPitch: scripted fetch/convert; shape-conformant preprocess; smoothing.
  - YAMNet: full input pipeline (log-mel) when needed; current runner assumes compatible Core ML input.
- Mapping & Expression
  - Pitch: per-note PB lane + vibrato controllers; bend range exposed via PE.
  - Poly: onset smoothing, quantize grid, min duration via PE.
  - Scenes: label/index mappings + debounce via PE; map to program/property sets.
- Integration
  - Route ML outputs simultaneously to Teatro + MetalViewKit; document canonical wiring.
- Tests/CI
  - Add non-interactive smokes (file → UMP assertions) per runner.
  - Add PE round-trip + chunking tests; Discovery Reply field checks.

## Definition of Done
- v1 (current)
  - Three runners compile and run locally; virtual endpoints created; optional PE snapshot via vendor JSON; example mappings present.
- v2 (target)
  - Spec-correct MIDI‑CI Discovery + PE (GET/SET) implemented and tested; unified property schema and mapping; file-based smokes and PE tests pass locally; demo app plays and renders with synchronized visuals.
  - midi2sampler integrated as the default in‑process instrument for demos; CLI `--render` path verified.

## Acceptance Criteria (per runner)
- Pitch: sustained f0 drives 32‑bit PB; new notes trigger NoteOn with consistent velocity; PE reflects bend range and smoothing; responds to CI Inquiry.
- Poly: file-based piano segment produces stable NoteOn/Off stream; threshold and voice limit applied; PE reflects thresholds and voice cap; responds to CI Inquiry.
- Scenes: stable top class above threshold produces Program Changes (or property set change); publishes/serves mapping via CI.

## Risks & Mitigations
- Model licensing/availability:
  - Mitigation: use fetch/convert scripts; exclude artifacts from git; document conversions.
- Latency under load:
  - Mitigation: buffering + back-pressure; optional JR timestamps; measure and log.
- CI toolchain drift:
  - Mitigation: keep scripting version-pinned; self-healing policy (run the commands locally and fix before declaring green).

## Ownership & Maintenance
- Ownership: CoreMLKit + runners (this track); MetalViewKit instrument CI integration (shared with visuals track).
- Maintenance policy: self-healing — always run the exact commands locally (see Commands) before status updates; fix locally if red.

## Commands (canonical)
- Fetch models
  - `swift run --package-path Packages/FountainApps coreml-fetch squeeze-net --out-dir Public/Models`
  - `swift run --package-path Packages/FountainApps coreml-fetch yam-net --out-dir Public/Models`
- Convert
  - `Scripts/apps/coreml-convert.sh crepe --saved-model /path/CREPE_SavedModel --frame 1024 --out Public/Models/CREPE.mlmodel`
  - `Scripts/apps/coreml-convert.sh basicpitch --saved-model /path/BasicPitch_SavedModel --out Public/Models/BasicPitch.mlmodel`
- Runners
  - Pitch: `swift run --package-path Packages/FountainApps ml-audio2midi --map-file Public/Models/pitch_props.example.json --publish-map`
  - Poly: `swift run --package-path Packages/FountainApps ml-basicpitch2midi --map-file Public/Models/poly_props.example.json --publish-map`
  - Scenes: `swift run --package-path Packages/FountainApps ml-yamnet2midi --map-file Public/Models/yamnet_program_map.example.json --send-program --publish-map`

---

Last updated: [maintain me]
