# FCIS-VRT Render Specification

## 1. Purpose

This document defines the canonical architecture for **FCIS-VRT Render** — a framework for verifying GUI rendering fidelity under MIDI 2.0 control, grounded in text-based prompts as semantic sources of truth. The legacy alias **PB-VRT** refers to this same render mode.

It unifies three domains:

1. **Prompt Semantics** — textual intent that defines the expected state of a GUI.  
2. **Probes** — modular capture and comparison mechanisms (RenderProbe, MIDIProbe, EmbeddingProbe).  
3. **Baselines** — canonical visual and semantic records used for regression validation.

---

## 2. Architectural Overview

Each GUI state in a test suite originates from a **Prompt**.  
The prompt defines semantic intent — e.g., _“Render the login form with email, password, and a disabled submit button.”_  
From this, the system renders a **visual baseline** and records MIDI 2.0 sequences for deterministic replay.

At runtime, FCIS-VRT Render compares current renderings against these baselines using multiple probes.

---

## 3. Prompt Contract

### 3.1 Structure

```yaml
id: "layout-login-screen"
text: "Render the login form with email, password, and a disabled submit button."
tags: ["UI", "auth", "form"]
modality: "visual"
embedding_model: "text-embedding-3-small"
hash: "sha256:e83f3a..."
```

### 3.2 Behavior

- The **prompt** is the root node for every regression entity.
- It links to rendered baselines, MIDI sequences, and embeddings.
- Prompts are immutable; only new versions with distinct hashes may supersede them.

### 3.3 Derived Artifacts

Each prompt yields:
- A **RenderProbe baseline** (`frame.png`)
- A **MIDIProbe sequence** (`sequence.ump`)
- An **EmbeddingProbe descriptor** (`embedding.json`)

---

## 4. Probe Contracts

### 4.1 RenderProbe

**Role:** Capture deterministic visual frames.

| Field | Type | Description |
|--------|------|-------------|
| `frameID` | String | Unique identifier for frame |
| `timestamp` | Double | MIDI transport tick |
| `pixels` | Binary | Encoded frame buffer (PNG) |
| `viewport` | Struct | `{width, height, scale}` |
| `colorProfile` | Enum | sRGB, P3, Rec.709 |

**Output:** `baseline/frameID.png`  
**Metric:** SSIM, pixel drift, temporal stability.

---

### 4.2 MIDIProbe

**Role:** Replay user input events deterministically using MIDI 2.0 Universal MIDI Packets (UMP).

| Field | Type | Description |
|--------|------|-------------|
| `sequenceID` | String | UUID of test sequence |
| `umpPackets` | Array | Raw MIDI 2.0 UMP events |
| `channel` | Int | MIDI channel identifier |
| `deviceName` | String | Logical input source |

**Behavior:**  
Synchronizes playback with RenderProbe captures using clock ticks.

---

### 4.3 EmbeddingProbe

**Role:** Compute high-level embeddings for semantic drift detection.

| Field | Type | Description |
|--------|------|-------------|
| `imageID` | String | Associated frame reference |
| `embedding` | [Float] | Feature vector |
| `model` | String | Model used (Vision FP or Core ML custom) |

**Metric:** Cosine or Euclidean distance between current and baseline embeddings.

**Swift Implementation:**

```swift
import Vision
import Foundation

struct EmbeddingProbe {
    func compute(from imageURL: URL) throws -> [Float] {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(url: imageURL, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first as? VNFeaturePrintObservation else {
            throw NSError(domain: "EmbeddingProbe", code: -1)
        }
        var vector = [Float](repeating: 0, count: 512)
        try result.computeDistance(&vector, to: result)
        return vector
    }
}
```

---

## 5. Prompt–Visual Binding

Each rendered baseline is stored alongside its prompt descriptor:

```
/data/visual-regression/
    /layout-login-screen/
        prompt.yaml
        baseline/frame001.png
        baseline/embeddings/frame001.json
        baseline/midi/sequence.ump
```

**Metadata:**

```json
{
  "prompt_hash": "sha256:e83f3a...",
  "frame_id": "frame001",
  "embedding_model": "text-embedding-3-small",
  "midi_sequence": "sequence.ump"
}
```

---

## 6. Comparison Pipeline

1. **Prompt Load** — identify canonical text prompt.  
2. **Replay** — execute MIDIProbe sequence.  
3. **Render** — capture frame via RenderProbe.  
4. **Embed** — compute visual embeddings.  
5. **Compare** — baseline vs current image + prompt similarity.

### Metrics

| Metric | Description |
|--------|-------------|
| SSIM | Structural similarity between images |
| ΔEmbedding | Cosine distance between feature vectors |
| Prompt–Visual | Text-to-Image embedding distance (optional CLIP/MLModel) |

---

## 7. Prompt–Visual Drift Metric

Optional when CLIP or text-image embedding models are available:

```
drift_score = α * (1 - SSIM) + β * ΔEmbedding + γ * (1 - PromptCosine)
```

Default weights: `α=0.5, β=0.3, γ=0.2`

---

## 8. CI Integration

- Run via `swift test --filter VisualRegressionTests`
- Each test outputs JSON summaries with all three metrics.
- Fail thresholds:
  - `SSIM < 0.98`
  - `ΔEmbedding > 0.05`
  - `PromptCosine < 0.90`

---

## 9. Example XCTest Stub

```swift
final class VisualRegressionTests: XCTestCase {
    func testLoginPromptVisualFidelity() throws {
        let prompt = Prompt.load("layout-login-screen")
        let render = try RenderProbe.capture()
        let drift = DriftAnalyzer.compare(prompt: prompt, render: render)
        XCTAssertLessThan(drift.totalScore, 0.05, "Visual drift exceeds tolerance")
    }
}
```

---

## 10. Compliance Summary

| Probe | Determinism | Output | Metric |
|--------|-------------|---------|---------|
| RenderProbe | High | PNG | SSIM |
| MIDIProbe | Exact | MIDI UMP | Timing |
| EmbeddingProbe | High | JSON | Cosine distance |
| Prompt Contract | Immutable | YAML | Semantic Fidelity |

---

## 11. Extensions

- Add prompt-to-audio modality (spoken design review).  
- Integrate diff visualizers into PatchBay test grid.  
- Support online prompt versioning and drift history in FountainKit.

---

**End of Specification**
