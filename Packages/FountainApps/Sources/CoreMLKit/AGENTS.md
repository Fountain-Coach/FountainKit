# CoreMLKit — Agent Guide

## Scope
- Thin Core ML utility library for loading models, compiling on demand, and running predictions.
- Complements MetalComputeKit without coupling ML to rendering/compute code.

## Targets
- `CoreMLKit` (library)
  - `CoreMLInterop`: load/compile models, create `MLMultiArray`, run predictions.
  - `ModelInfo`: summarize inputs/outputs (names, types, shapes).
  - `VisionAudioHelpers`: convenience for `CVPixelBuffer` and audio arrays.

## Usage
- Load a model and run a prediction:
  ```swift
  import CoreMLKit
  let loaded = try CoreMLInterop.loadModel(at: "/path/Model.mlmodel")
  let summary = ModelInfo.summarize(loaded.model)
  let arr = try CoreMLInterop.makeMultiArray([Float](repeating: 0, count: 1*224*224), shape: [1,224,224])
  let out = try CoreMLInterop.predict(model: loaded.model, inputs: [summary.inputs.first!.name: arr])
  ```
- CLI demo:
  - `COREML_MODEL=/path/to/Model.mlmodel[c] swift run --package-path Packages/FountainApps coreml-demo`

## Fetching sample models
- Use the fetcher to download SqueezeNet or any URL:
  - `swift run --package-path Packages/FountainApps coreml-fetch squeeze-net --out-dir Public/Models`
  - `swift run --package-path Packages/FountainApps coreml-fetch url-fetch https://example.com/Model.mlmodel --out-dir Public/Models`
- Conversion notes for CREPE/BasicPitch:
  - `swift run --package-path Packages/FountainApps coreml-fetch notes`

## Converting models (Scripts)
- Use the shell helper to convert common formats with coremltools (venv auto-bootstraps under `.coremlvenv`):
  - `Scripts/apps/coreml-convert.sh crepe --saved-model /path/CREPE_SavedModel --frame 1024 --out Public/Models/CREPE.mlmodel`
  - `Scripts/apps/coreml-convert.sh basicpitch --saved-model /path/BasicPitch_SavedModel --out Public/Models/BasicPitch.mlmodel`
  - `Scripts/apps/coreml-convert.sh keras --h5 /path/model.h5 --frame 1024 --out Public/Models/Model.mlmodel`
  - `Scripts/apps/coreml-convert.sh tflite --tflite /path/model.tflite --frame 1024 --out Public/Models/Model.mlmodel`

## Audio → MIDI 2.0 (Pitch) — Demo
- Executable: `ml-audio2midi`
  - Mic or file → pitch (CREPE model or DSP fallback) → MIDI 2.0 NoteOn/Pitch Bend on a CoreMIDI virtual endpoint.
  - Examples:
    - `swift run --package-path Packages/FountainApps ml-audio2midi --file /path/audio.wav`
    - `swift run --package-path Packages/FountainApps ml-audio2midi --model /path/CREPE.mlmodel`
    - `swift run --package-path Packages/FountainApps ml-audio2midi --destination "Your DAW"`
  - Behavior:
    - If `--model` is provided and outputs a 360‑bin distribution, decodes as CREPE (20‑cent bins, C1 base).
    - If `--model` outputs a single scalar, treats it as f0 in Hz.
    - Otherwise falls back to autocorrelation pitch.
  - Mapping:
    - Computes nearest note and 14‑bit pitch bend around ±2 semitones.
    - Sends MIDI 2.0 Channel Voice (64‑bit UMP) messages.
  - CI vendor JSON:
    - `--map-file` to include additional properties; `--publish-map` to publish on startup and Discovery Inquiry.
  - Example properties file:
    - `Public/Models/pitch_props.example.json`
    - Run: `swift run --package-path Packages/FountainApps ml-audio2midi --map-file Public/Models/pitch_props.example.json --publish-map`
  - MIDI2 Instrument Bridge (local render): add `--render` to play in‑process while still sending MIDI.

## Audio → MIDI 2.0 (Poly) — Demo
- Executable: `ml-basicpitch2midi`
  - Mic or file → polyphonic note activation via BasicPitch‑style model or a spectral fallback.
  - Examples:
    - `swift run --package-path Packages/FountainApps ml-basicpitch2midi --file /path/audio.wav`
    - `swift run --package-path Packages/FountainApps ml-basicpitch2midi --model /path/BasicPitch.mlmodel --threshold 0.6`
  - Behavior:
    - If `--model` outputs a per‑pitch probability vector/matrix, applies thresholding and hysteresis to emit NoteOn/NoteOff.
    - If no model is provided, uses a spectral peak picker to emit up to `--max-notes` notes per frame.
  - Mapping:
    - Emits MIDI 2.0 NoteOn/NoteOff per detected pitch. Per‑note pitch bend can be added later when model confidence exposes fine detune.
  - CI vendor JSON:
    - `--map-file` to include additional properties; `--publish-map` to publish on startup and Discovery Inquiry.
  - Example properties file:
    - `Public/Models/poly_props.example.json`
    - Run: `swift run --package-path Packages/FountainApps ml-basicpitch2midi --map-file Public/Models/poly_props.example.json --publish-map`
  - MIDI2 Instrument Bridge (local render): add `--render` to play in‑process while still sending MIDI.

## Audio Events → MIDI 2.0 (Scenes)
- Executable: `ml-yamnet2midi`
  - Mic or file → YAMNet classification → scene changes via Program Change + vendor JSON snapshot.
  - Examples:
    - Fetch model + labels: `swift run --package-path Packages/FountainApps coreml-fetch yam-net --out-dir Public/Models`
    - Convert to Core ML (if needed): `Scripts/apps/coreml-convert.sh tflite --tflite Public/Models/YAMNet.tflite --frame 15600 --out Public/Models/YAMNet.mlmodel`
    - Run: `swift run --package-path Packages/FountainApps ml-yamnet2midi --model Public/Models/YAMNet.mlmodel --labels Public/Models/yamnet_class_map.csv --send-program`
    - With mapping file: `swift run --package-path Packages/FountainApps ml-yamnet2midi --model Public/Models/YAMNet.mlmodel --labels Public/Models/yamnet_class_map.csv --map-file Public/Models/yamnet_program_map.json --send-program --publish-map`
  - Behavior:
    - Picks the top class above `--threshold`, rate‑limited by `--cooldown-ms`.
    - Sends MIDI 2.0 Program Change (optional) and a vendor JSON SysEx7 snapshot: `{sceneIndex, sceneLabel, confidence}`.
    - Optional mapping JSON format (both keys supported):
      ```json
      {
        "programMap": { "Speech": 1, "Music": 5, "Drum": 9 },
        "programMapByIndex": { "0": 1, "1": 5, "2": 9 },
        "defaultProgram": 0
      }
      ```
    - Example mapping file: `Public/Models/yamnet_program_map.example.json`
    - With `--publish-map`, the runner publishes the mapping snapshot on startup and replies to MIDI‑CI Discovery Inquiry with the same vendor JSON (CI-framed 0x7E/0x7F/0x0D/0x7C).

## Model curation
- Place first‑party sample models under `Public/Models/` and third‑party under `External/Models/`.
- Do not commit `.mlmodelc`. Compile at runtime (`MLModel.compileModel`) or via a dev script.
 - Public starter set (suggested):
   - Image: Apple SqueezeNet (`https://docs-assets.developer.apple.com/coreml/models/SqueezeNet.mlmodel`)
   - Audio (pitch): CREPE‑tiny (convert from TF via coremltools; multiple public conversions exist)
   - Audio (events): YAMNet (convert from TF/TFLite via coremltools)
   - Poly transcription: BasicPitch (convert from TF; feed frames → pitch matrix)

## Compute units
- We default to `.all`. Override via `CoreMLInterop.loadModel(at:computeUnits:)` (e.g., `.cpuOnly`, `.cpuAndGPU`, `.cpuAndNeuralEngine`).

## Ownership policy (self‑healing)
- We run the same commands locally before reporting green. Example canonical commands:
  - Capabilities & compute: `swift run --package-path Packages/FountainApps metalcompute-demo`
  - ML demo: `COREML_MODEL=... swift run --package-path Packages/FountainApps coreml-demo`
- If something fails, we read the logs and fix here before telling you it’s green.

## Notes
- This repo targets macOS 14; Core ML is fully available. If you need broader support, gate features behind availability checks.
- For vision/audio models, use `VisionAudioHelpers` to build inputs quickly without additional dependencies.
