# Engraver Studio as a GUI App Factory

This document consolidates Fountain Coach’s internal research on image-based GUI production and turns it into an operational blueprint for Engraver Studio. The underlying research (“Optimizing GUI App Creation with Image-Based Mocks and Fountain Coach Tools”, internal memo, 2025‑03‑12) made three key observations:

1. **Mocks are data, not artefacts** – every exported screen must carry structured metadata so engines can interpret layout, typography, and interaction intent.
2. **Engraver, ScoreKit, and RulesKit already cover the workload** – Engraver gives deterministic rendering, ScoreKit supplies typographic grids, and RulesKit encodes layout policy. When combined, they outperform ad‑hoc UI frameworks.
3. **Automation beats hand-tuning** – detection, normalisation, and validation pipelines must be re‑runnable, so every mock-to-code transformation can be proven, diffed, and rolled back.

The goal of this markdown is to turn those findings into a self-contained story that supports both human collaborators and LLM agents. Feed the factory a design mock, and it returns a tested, cross-platform Teatro scene with validated styling and Fountain Coach wiring—no guesswork, no platform lock-in, and measurable compliance.

This document extends the paper into a working blueprint for an “Engraver GUI Factory”. It is written for both humans and LLM collaborators who will build, maintain, and extend this capability. The aim is simple: **feed the factory a design mock, and receive a cross-platform Teatro scene with validated styling, instrumentation, and Fountain Coach wiring**. No guesswork, no divergence between Figma and runtime, and no surprises when the same blueprint is rendered on macOS, Linux, or a headless CI agent.

We will walk through:

1. The conceptual model—blueprints, detectors, rule engines, and the iterative Studio workflow.
2. The implementation plan—broken into phases, each grounded in an explicit deliverable.
3. The supporting packages (Engraver, ScoreKit, RulesKit, Teatro) and how they speak to each other.
4. The automation and QA story that keeps the factory deterministic.
5. The human and AI collaboration patterns that make the tooling approachable.

---

## 1. From Mock to Blueprint: A Shared Vocabulary

The research memo stresses that mocks must ship with machine-readable structure. We translate that into the **Engraver Blueprint**.

- **Raw Assets**: each mock resides in `/EngraverStudio/Blueprints/<name>/mock.png`. Designers can use any tool (Figma export, Teatro’s own rasterizer, a photograph of a whiteboard). What matters is that the PNG captures the intended state.

- **Blueprint Manifest (`mock.eng.json`)**: a structured description of the mock that mirrors the paper’s “Layer Taxonomy”. Top-level sections:
  - `artboard`: canvas size, base colour, density.
  - `layers`: ordered list of UI primitives (text, button, panel, image). Each layer references the bounding box inside the mock, the z-order, and the intended role (e.g. “primary CTA”).
  - `interactions`: hints for interactive behaviour (hover target, scroll region, chat input).
  - `semantics`: attachments for ScoreKit (font family, weight), RulesKit (minimum contrast, alignment rule), and Engraver (token stream reference).

- **Blueprint Kit**: a new Swift package, `EngraverBlueprintKit`, provides Codable models, JSON schema validation, and helper utilities for merging blueprints. LLMs can rely on these types to manipulate mocks safely.

This vocabulary honours the research mandate for “baseline asset requirements” and ensures designers, engineers, and automated agents speak the same language about layers, anchors, and validation rules.

---

## 2. Detection Pipeline: Turning Pixels into Structure

Implementing the “image-derived layout extraction” pipeline from the memo requires a CLI and modular analyzers that cooperate instead of competing.

### 2.1 `engraver blueprint import`

This command ingests `mock.png`, performs the following steps, and emits an updated `mock.eng.json`:

1. **Raster Analysis (Teatro)**: using Teatro’s SDL raster tools, we detect distinct regions (connected components, clusters of similar colour). We can lean on Teatro’s existing timeline renderer to maintain pixel-perfect fidelity—an advantage highlighted in the paper’s “Normalization Grid” concept.

2. **Text Segmentation (ScoreKit)**: text regions are forwarded to ScoreKit, which applies optical character recognition tuned to our font families. ScoreKit returns the resolved font size, line height, letter spacing, and baseline offsets. These metrics anchor our eventual Teatro scene in the same typographic grid described in the mock.

3. **Shape Classification (RulesKit)**: rectangles, circles, and complex polygons are mapped to UI primitives. RulesKit tags them with constraints (minimum hit target, colour contrast) so we can later verify compliance.

4. **Semantic Mapping**: We merge detection results with the existing blueprint file, preserving any manual annotations. Every layer now carries both the visual geometry and the behaviour hints (e.g. “chat input field”, “streaming token overlay”).

### 2.2 Determinism and Repeatability

Determinism is essential—re-running the pipeline must yield identical output. We enforce that by:

- Sorting detected layers by (y, x) position.
- Snapping bounding boxes to a grid (configurable per ScoreKit profile).
- Hashing the blueprint file after every run and storing the hash in `mock.eng.hash`. CI can confirm that detection output hasn’t changed unexpectedly.

### 2.3 Developer Ergonomics

`engraver blueprint import` prints a succinct report:

```
Detected 12 layers:
  [text] ChatTitle – 512×48 @ (32, 28) – matched ScoreKit style “Display/Title”
  [shape] MainPanel – 640×480 @ (24, 96) – applied RulesKit rule PAD_24
  …
```

If detection fails (e.g. ambiguous layers), the CLI offers prompts to annotate them manually. This is crucial for LLM workflows—augmented instructions can be woven into blueprint files directly.

---

## 3. Engraver Blueprint Kit & Supporting Packages

Implementing the factory requires the three existing Fountain Coach toolkits to collaborate:

- **Engraver** remains the deterministic renderer. It produces Teatro scenes, handles diagnostics, and now exposes the blueprint overlay inside Engraver Studio.

- **ScoreKit** supplies typographic grids and style definitions. We create a `ScoreKitEngraverBridge` module that translates detection metrics into ScoreKit styles (e.g. mapping `fontSize: 18` to the “Body/Medium” style).

- **RulesKit** enforces layout constraints. Each blueprint layer references one or more RulesKit rules. During validation the ruleset is evaluated, and warnings are surfaced directly inside Engraver Studio.

- **Teatro** renders the final scene. Because Teatro is cross-platform and runs in SDL, we avoid being locked to macOS frameworks—a key motivation in the paper.


## 4. Engraver Studio Integration

The research memo describes a “review console” where designers and engineers iterate together. Engraver Studio becomes that console.

### 4.1 Blueprints Tab

We add a dedicated tab with four panels:

1. **Mock Preview**: the raw PNG, scaled to fit the view.
2. **Teatro Preview**: a live render of the generated Teatro scene. Users can toggle between projected states (loading, streaming, error).
3. **Rules Overview**: a table of RulesKit results (pass/fail). Clicking a failed rule highlights the offending layer in both previews.
4. **Metadata Editor**: inline forms for layer semantics (e.g. reclassifying a button or assigning a data source).

Thanks to Engraver’s diagnostics panel, we can stream logs (e.g. “RulesKit: PAD_24 violated by ChatPanel”) without leaving the Studio.

### 4.2 Scaffold Generator

Button: **“Create Teatro App”**. When clicked:

- Generates an Engraver project under `Apps/<BlueprintName>/`.
- Produces:
  - `Scene.swift`: Teatro scene definition with components wired to view-model outlets.
  - `SceneViewModel.swift`: Engraver view model stub (built on `GatewayChatClient`).
  - `ScoreKitStyles.swift`: typographic tokens.
  - `RulesKitRules.json`: exported ruleset.
  - `Tests/SceneSnapshotTests.swift`: Engraver renderer snapshot tests.

The generator marks each file with provenance metadata (`GeneratedFromBlueprint: <hash>`), enabling regeneration without manual conflicts.

### 4.3 Validation Workflow

After manual tweaks, `engraver blueprint validate` runs:

1. RulesKit evaluation.
2. Engraver snapshot rendering (into `/snapshots`).
3. Diff against original mock (using the thresholds defined in the paper’s “Visual Diff Strategy”).

Results are displayed in Studio and returned as exit codes for CI. Designers and developers always know whether the current scene honours the original design.

---

## 5. Automation & QA

To maintain trust in the factory, automation is essential. Every mock must behave like a contract; CI is where we enforce it.

### 5.1 Nightly Regression Job

`Scripts/ci-blueprints.sh` iterates over every blueprint:

- Runs detection (`engraver blueprint import`).
- Runs validation (RulesKit + snapshot).
- Reports deviations via Slack or GitHub annotations.

Because every blueprint carries a hash, we quickly spot differences. When they do appear, the CI diff highlights which layers changed.

### 5.2 Cross-Platform Rendering

Teatro’s headless renderer lets us spin up SDL windows in CI. We run the same scene on macOS and Linux, capture the rendered output, and ensure pixel hashes match within tolerance. This guards against platform-specific drift—the “portability matrix” the research memo calls out.

### 5.3 Documentation & Training

In `/docs/engraver-factory.md` (this document) we provide:

- Step-by-step guide (from mock ingestion to app export).
- FAQ for detection anomalies (e.g. “How do I mark a gradient background?”).
- Tips for LLM interactions (“How to request Engraver to regenerate a blueprint”, etc.).

It mirrors the “team playbook” requested by the research group, ensuring new contributors onboard quickly.

---

## 6. Interaction with ScoreKit & RulesKit

Because Engraver Studio is the GUI factory, we treat ScoreKit and RulesKit as first-class citizens.

- **ScoreKit**: blueprint layers referencing typography automatically resolve to ScoreKit styles. Studio displays style previews (sample text, line height) so designers can confirm the style set. When the blueprint is exported, ScoreKit styles accompany the scene, ensuring the downstream Teatro app renders text exactly as intended.

- **RulesKit**: each blueprint includes a ruleset derived from detection plus manual overrides. Studio renders pass/fail badges. RulesKit’s engine can run interactively (e.g. when a designer edits paddings), providing instant feedback. The rules cover:
  - Accessibility (contrast, touch target).
  - Layout (alignment, spacing intervals).
  - Behaviour policies (e.g. chat input must support copy/paste).

The factory now becomes self-correcting: designers see when they stray from policy, engineers never merge a scene that violates core rules, and LLMs can reason about rule results in conversation.

---

## 7. Human & LLM Collaboration

The research’s final chapter emphasises collaboration between humans and automation. Our implementation supports three flows:

1. **Designer → Blueprint**: Designers drop a mock into the Blueprint directory and run `engraver blueprint import`. The CLI summarises the blueprint and logs into Engraver Studio for immediate review.

2. **Engineer → App Scaffold**: Engineers open Studio, inspect the blueprint, and click “Create Teatro App”. The scaffold includes Engraver view models ready to connect to Gateway and Fountain Store services.

3. **LLM → Maintenance**: LLM agents can safely modify blueprints or regenerate scenes by using the CLI commands. Because the schema, hash, and tests are canonical, automated agents never drift outside expected behaviour.

When something fails (e.g. detection ambiguous), the CLI produces actionable instructions (“Layer 7: ambiguous text bounding box. Add `boundsOverride` to mock.eng.json”). LLMs can then patch the file and re-run, while humans can see the same hints in Studio.

---

## 8. Putting It All Together

At the end of these phases, Engraver Studio is no longer a hand-built macOS app. It is a **GUI factory** that:

- ingests image mocks,
- generates structured blueprints,
- validates them against ScoreKit typography and RulesKit policies,
- scaffolds Teatro-based apps ready for Fountain Coach orchestration,
- keeps everything deterministic through Engraver’s rendering engine,
- and automates regression detection across platforms.

The journey from “Optimizing GUI App Creation with Image-Based Mocks and Fountain Coach Tools” to this implementation plan is cohesive: we took the research’s theoretical loops (detection, normalisation, governance) and mapped them into commands, packages, Studio tabs, and CI checks. Designers see what they shipped, developers code against verified structures, and LLMs have a safe playground to manipulate the assets programmatically. Most importantly, we no longer guess our way through UI creation—Engraver Studio, ScoreKit, and RulesKit ensure every mock becomes a faithful, tested, cross-platform Teatro experience.
