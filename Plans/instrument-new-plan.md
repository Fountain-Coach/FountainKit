# instrument-new — Canonical Instrument Template (Plan)

This plan defines the `instrument-new` tool and the default template for creating new Fountain instruments. It makes the AGENTS + linter rules executable: every instrument is a MIDI 2.0 instrument with a surface, a spec, facts, and tests.

Status (2025-11-18)
- This document captures the desired shape; implementation work is open.
- `instrument-lint` exists and performs structural checks; `instrument-new` will sit beside it in `FountainTooling`.

## 1. Intent

We want a single entry point for creating new instruments that:

- Treats **every instrument as a MIDI 2.0 instrument** (CI/PE surface, facts in FountainStore, discoverable by the MIDI host).
- Always creates a **surface**:
  - For visual instruments: an event‑graph GUI surface (MetalViewKit or FountainGUIKit).
  - For non‑visual instruments: a logical surface over PE properties.
- Produces artifacts that immediately satisfy:
  - `Design/INSTRUMENT_REQUIREMENTS.md`.
  - `Design/INSTRUMENT_LINT_STORY.md`.
  - `Tools/instruments.json`.
  - `Scripts/openapi/openapi-to-facts.sh`.

## 2. Inputs and Modes

`instrument-new` takes a small, structured input:

- Required:
  - `appId` — short id for the instrument (e.g., `llm-chat`, `orbit-canvas`).
  - `agentId` — canonical agent id (e.g., `fountain.coach/agent/llm-chat/service`).
  - `specName` — spec filename under `openapi/v1` (e.g., `llm-chat.yml`).
- Optional flags:
  - `--graph=fgk|metalview` — preferred UI/event graph host:
    - `fgk` → FountainGUIKit (`FGKNode`, `FGKRootView`, `FGKEvent`).
    - `metalview` → MetalViewKit canvas node.
  - `--visual` (default true) — instrument has a visual surface and must get PB‑VRT scaffolding.
  - `--no-app` — seed/spec/tests only; no executable app surface yet (for backend‑only instruments).

Everything else (Teatro prompt, facts, test layout) is derived from these inputs.

## 3. Artifacts Created/Updated

For a given `{appId, agentId, specName}`, `instrument-new` will:

### 3.1 OpenAPI spec stub

- Add or update `Packages/FountainSpecCuration/openapi/v1/<specName>` with a minimal valid OpenAPI 3.1 document:
  - `info.title` set to a human‑readable instrument name (`<AppId> Instrument API`).
  - `paths` containing at least:
    - One **state** route (e.g., `GET /state` or `/prompt/state`).
    - One **command** route (e.g., `POST /set`, `/prompt/set`, or `/chat/request`).
  - Each operation tagged with `x-fountain.allow-as-tool: true`.
- Append a row to `Packages/FountainSpecCuration/openapi/README.md`:
  - Name, version, and link to `v1/<specName>`.

### 3.2 Facts wiring from OpenAPI

- Append a mapping to `Scripts/openapi/openapi-to-facts.sh`:

  ```bash
  "<specName>:<agentId>"
  ```

- This is generic; no app‑specific branching.

### 3.3 Teatro prompt + facts seeder

- Create a new executable target `<appId>-seed` in `Packages/FountainApps/Package.swift`:

  ```swift
  .executableTarget(
      name: "<appId>-seed",
      dependencies: [
          .product(name: "FountainStoreClient", package: "FountainCore"),
          .product(name: "LauncherSignature", package: "FountainCore")
      ],
      path: "Sources/<appId>-seed"
  )
  ```

- Add `Sources/<appId>-seed/main.swift` that:
  - Respects `FOUNTAIN_SKIP_LAUNCHER_SIG`.
  - Seeds FountainStore corpus `<appId>` with:
    - `pageId = "prompt:<appId>"`.
    - Segment `prompt:<appId>:teatro` (`kind: teatro.prompt`) with a starter Teatro prompt describing:
      - Scene, layout, primary properties, MIDI‑CI expectations.
    - Segment `prompt:<appId>:facts` (`kind: facts`) with a JSON stub:
      - `instruments[]` (id, manufacturer, product, instanceId, displayName).
      - `pe[]` listing initial property names (e.g., `canvas.zoom`, `prompt.text`, `thread.scrollOffset`).
      - `invariants[]` as a small set of textual invariants to refine later.

### 3.4 Instrument index entry

- Append a record to `Tools/instruments.json`:

  ```json
  {
    "appId": "<appId>",
    "agentId": "<agentId>",
    "corpusId": "<appId>",
    "spec": "<specName>",
    "runtimeAgentId": null,
    "testModulePath": "Packages/FountainApps/Tests/<AppId>Tests",
    "snapshotBaselinesDir": "Packages/FountainApps/Tests/<AppId>Tests/Baselines",
    "requiredTestSymbols": [
      "<AppId>Tests",
      "<AppId>SnapshotTests"
    ]
  }
  ```

- If `--visual=false`, `snapshotBaselinesDir` and `SnapshotTests` can be omitted; otherwise they are required.

### 3.5 Test scaffolding (surface + PE behaviour)

Under `Packages/FountainApps/Tests/<AppId>Tests/`:

- `Baselines/.gitkeep` (when `--visual`).
- `<AppId>Tests.swift`:
  - Imports the app surface target when present, plus the graph host (`FountainGUIKit` or MetalViewKit).
  - Instantiates a minimal surface:
    - For `fgk`:

      ```swift
      let frame = NSRect(x: 0, y: 0, width: 640, height: 400)
      let node = FGKNode(instrumentId: "<agentId>", frame: frame, properties: [], target: nil)
      let view = <AppId>SurfaceView(frame: frame, rootNode: node)
      let target = <AppId>InstrumentTarget(view: view, node: node)
      node.target = target
      ```

  - At least one test that:
    - Sends a small sequence of events (`FGKEvent.keyDown`, `scroll`, etc.) into the target.
    - Asserts state changes that match initial property semantics (e.g., pan, zoom, prompt editing).

- `<AppId>SnapshotTests.swift` (when `--visual`):
  - Renders the surface into an image at a canonical size.
  - Compares against PNG baselines using the existing snapshot utilities (BlankApp / FountainGUI demo pattern).

### 3.6 Optional app surface target

If `--no-app` is not set, create a thin event‑graph app:

- New executable target `<appId>-app` in `Packages/FountainApps/Package.swift`:

  ```swift
  .executableTarget(
      name: "<appId>-app",
      dependencies: [
          .product(name: "FountainGUIKit", package: "FountainGUIKit"),
          .product(name: "FountainAICore", package: "FountainCore"),
          // Optional: ProviderLocalLLM, MetalViewKit, etc.
      ],
      path: "Sources/<appId>-app"
  )
  ```

- Implementation:
  - `NSApplication` + `NSWindow` host.
  - For `fgk`:
    - `<AppId>SurfaceView: FGKRootView` to draw a minimal representation.
    - `<AppId>InstrumentTarget: FGKEventTarget` to interpret keyboard/gesture events.
  - App respects `FOUNTAIN_SKIP_LAUNCHER_SIG` and uses the same instrument id as in `Tools/instruments.json`.

## 4. Tool Behaviour and Validation

`instrument-new` should be implemented as:

- A new executable target `instrument-new` under `Packages/FountainTooling/Sources/instrument-new`.
- A thin shell wrapper `Scripts/instrument-new` that:
  - Passes CLI args through.
  - Sets `FOUNTAINSTORE_DIR` when needed for seeding.

On each run, `instrument-new` must:

1. Generate/update all artifacts listed above.
2. Run scoped OpenAPI → facts seeding:

   ```bash
   FOUNTAINSTORE_DIR=.fountain/store CORPUS_ID=agents \
   swift run --package-path Packages/FountainTooling -c debug openapi-to-facts Packages/FountainSpecCuration/openapi/v1/<specName> --agent-id <agentId> --seed --allow-tools-only
   ```

3. Run structural lint:

   ```bash
   FOUNTAINSTORE_DIR=.fountain/store Scripts/instrument-lint.sh
   ```

   - Fix any **structural** failures (missing spec entry, test paths, baselines, symbols) before returning.
   - Facts warnings are allowed temporarily but should be logged and reported.

4. Run tests for the new module:

   ```bash
   swift test --package-path Packages/FountainApps -c debug --filter <AppId>Tests
   ```

   - If tests fail to compile or run, `instrument-new` prints a focused error and exits non‑zero.

## 5. AGENTS Integration and Maintenance

- Root `AGENTS.md` should be updated to:
  - Mention `Plans/instrument-new-plan.md` in the Plans Index.
  - Declare `instrument-new` as the canonical way to add instruments.
- Future AGENT rules for instruments can be enforced by:
  - Extending `instrument-lint` (no special cases per app).
  - Extending `instrument-new`’s template (so new instruments inherit the rules by default).

This plan is the source of truth for the `instrument-new` tool. Implementation work belongs under `Packages/FountainTooling` and must keep this document in sync when behaviour changes.

