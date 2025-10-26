# CoreMLKit — Agent Guide

CoreMLKit is a thin Core ML utility library for loading models, compiling on demand, and running predictions. It complements MetalComputeKit without coupling ML to rendering/compute code.

Targets
`CoreMLKit` (library) includes `CoreMLInterop` (load/compile models, make `MLMultiArray`, run predictions), `ModelInfo` (summarize input/output names, types, shapes), and `VisionAudioHelpers` (build `CVPixelBuffer` and audio arrays).

Usage
Load a model and run a prediction:
```swift
import CoreMLKit
let loaded = try CoreMLInterop.loadModel(at: "/path/Model.mlmodel")
let summary = ModelInfo.summarize(loaded.model)
let arr = try CoreMLInterop.makeMultiArray([Float](repeating: 0, count: 1*224*224), shape: [1,224,224])
let out = try CoreMLInterop.predict(model: loaded.model, inputs: [summary.inputs.first!.name: arr])
```
CLI demo: `COREML_MODEL=/path/to/Model.mlmodel[c] swift run --package-path Packages/FountainApps coreml-demo`

Fetching sample models
Use the fetcher to download SqueezeNet or any URL: `swift run --package-path Packages/FountainApps coreml-fetch squeeze-net --out-dir Public/Models` or `… coreml-fetch url-fetch https://…/Model.mlmodel --out-dir Public/Models`. Conversion notes for CREPE/BasicPitch: `swift run --package-path Packages/FountainApps coreml-fetch notes`.

Converting models (scripts)
Use `Scripts/apps/coreml-convert.sh` to convert common formats with coremltools (venv auto‑bootstraps under `.coremlvenv`). Examples: `… crepe --saved-model /path/CREPE_SavedModel --frame 1024 --out Public/Models/CREPE.mlmodel`, `… basicpitch --saved-model /path/BasicPitch_SavedModel`, `… keras --h5 /path/model.h5`, `… tflite --tflite /path/model.tflite`.

Audio → MIDI 2.0 demos
- Pitch (`ml-audio2midi`): mic or file → pitch (CREPE or DSP fallback) → MIDI 2.0 NoteOn/Pitch Bend on a CoreMIDI virtual endpoint. If the model outputs 360 bins, decode as CREPE (20‑cent bins, C1 base); if a scalar, treat as f0 in Hz; otherwise fall back to autocorrelation. Compute nearest note and 14‑bit pitch bend (±2 semitones) and send 64‑bit UMP. Include CI vendor JSON via `--map-file` and publish on startup with `--publish-map`. Example properties: `Public/Models/pitch_props.example.json`. Add `--render` to play locally while sending MIDI.
- Poly (`ml-basicpitch2midi`): mic or file → BasicPitch‑style matrix or spectral fallback. Threshold/hysteresis emit NoteOn/Off. Optional mapping via `--map-file` (e.g., `Public/Models/poly_props.example.json`), publish with `--publish-map`, and render locally with `--render`.
- Scenes (`ml-yamnet2midi`): mic or file → YAMNet classification → Program Change and vendor JSON snapshot. Fetch/labels via `coreml-fetch yam-net`; convert TFLite if needed. Optional mapping JSON supports both `programMap` and `programMapByIndex`; with `--publish-map`, publish on startup and reply to Discovery Inquiry with the same vendor JSON.

Model curation
Place first‑party sample models under `Public/Models/` and third‑party under `External/Models/`. Do not commit `.mlmodelc`; compile at runtime or via a dev script. Suggested starters: Apple SqueezeNet, CREPE‑tiny (converted), YAMNet (converted), BasicPitch (converted).

Compute units
Defaults to `.all`. Override with `CoreMLInterop.loadModel(at:computeUnits:)` (e.g., `.cpuOnly`, `.cpuAndGPU`, `.cpuAndNeuralEngine`).

Ownership policy (self‑healing)
We run the same commands locally before reporting green. Canonical checks: `swift run --package-path Packages/FountainApps metalcompute-demo` and `COREML_MODEL=… swift run --package-path Packages/FountainApps coreml-demo`. If something fails, we read the logs and fix here before telling you it’s green.

Notes
This repo targets macOS 14. Gate broader support behind availability checks. For vision/audio models, use `VisionAudioHelpers` to build inputs without extra deps.
