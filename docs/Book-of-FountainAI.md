# The Book of FountainAI

This document is a fast technical overview of FountainAI as implemented in this repository. It is written for people and LLMs that already work in the codebase and want a compact mental model of the system surface, not a full history.

---

## 1. Core Mental Model

FountainKit has three planes that work together:

- **MIDI 2.0 execution plane** – `midi-instrument-host` plus `FountainTelemetryKit` (`MIDI2Core`, `MIDI2Transports`, `SSEOverMIDI`) expose agent capabilities as MIDI‑CI Property Exchange properties and route PE GET/SET in real time. This is the “live pulse” that drives instruments.
- **Spec/control plane (HTTP + OpenAPI)** – services in `FountainServiceKit-*` and `FountainTooling` expose OpenAPI‑described HTTP APIs. Apple’s Swift OpenAPI Generator plus `NIOOpenAPIServerTransport` host these as servers.
- **Fact/prompt plane (FountainStore)** – prompts, agent facts, instrument index entries, and tool metadata live in FountainStore and are read by both the HTTP services and the MIDI host.

OpenAPI specs describe what an agent or service can do. `openapi-to-facts` turns those specs into PE facts and seeds them into FountainStore. `midi-instrument-host` then reads those facts and exposes them over MIDI 2.0 CI/PE. Tools Factory, `instrument-new`, and `instrument-lint` live in the spec/control plane and keep the facts and instrument catalog consistent so that the execution plane can remain fast and simple.

---

## 2. Packages and Runtime

The root `Package.swift` depends on local packages under `Packages/`. The key ones are:

- `FountainCore` – runtime primitives, HTTP server (`IntegrationRuntime/*`, `OpenAPI/NIOOpenAPIServerTransport.swift`), FountainStore client.
- `FountainTelemetryKit` – MIDI 2.0 stack (`MIDI2Core`, `MIDI2Transports`, `SSEOverMIDI`, `FlexBridge`).
- `FountainServiceKit-*` – service libraries that own OpenAPI specs and `OpenAPIHandlers.swift` implementations.
- `FountainTooling` – tools (`openapi-jsonify`, `openapi-to-facts`, `instrument-lint`, `instrument-new`, OpenAPI curator) and corresponding services.
- `FountainApps` – servers, CLIs, and apps, including `midi-instrument-host`.
- `FountainSpecCuration` – curated OpenAPI documents (`openapi/v1/*.yml`) and coverage docs.

HTTP services follow a uniform pattern: a library target with `openapi.yaml` + `openapi-generator-config.yaml`, a generated `APIProtocol`, a hand‑written implementation file (for example `OpenAPIHandlers.swift`), and an executable that builds an `NIOOpenAPIServerTransport`, wraps it in `NIOHTTPServer`, and binds to a port.

The MIDI 2.0 host is implemented as an app in `Packages/FountainApps/Sources/midi-instrument-host`, backed by the transports and CI/PE helpers from `FountainTelemetryKit`.

---

## 3. Specs, Tools Factory, and Tool Registration

Specs live under `Packages/FountainSpecCuration/openapi`. `README.md` in that directory documents versioning and the `x-fountain.*` extensions used to mark which operations should be exposed as tools. For tools registration, the central service is Tools Factory, specified by `openapi/v1/tools-factory.yml`, implemented in `Packages/FountainServiceKit-ToolsFactory`, and hosted by `Packages/FountainApps/Sources/tools-factory-server`.

Tools Factory has two main endpoints: `/tools` lists registered tools, and `/tools/register` accepts an OpenAPI document and creates function definitions in FountainStore (function id, description, HTTP method/path, input schema, and the original OpenAPI fragment). The helper `openapi-jsonify` (`Packages/FountainTooling/Sources/openapi-jsonify`) normalizes specs to JSON. Scripts under `Scripts/openapi/` (for example `register-teatro-guide-as-tools.sh`, `register-instrument-new-as-tools.sh`) use `openapi-jsonify` and POST the result to `/tools/register`. This is the standard path to make a new OpenAPI operation callable by an LLM.

---

## 4. FountainStore, Facts, and Agents

FountainStore is the document store used throughout the system. The client lives in `Packages/FountainCore/Sources/FountainStoreClient`, and the default local root is `.fountain/store` at the repository root. Interactive surfaces persist their Teatro prompts and instrument “facts” here. Seeders under `Packages/FountainApps/Sources/<appId>-seed` create a corpus (often `<appId>`), a page `prompt:<appId>`, a `teatro.prompt` segment (prompt text), and a `facts` segment (JSON describing instruments, properties, and invariants). Prompts and facts are never duplicated in ad‑hoc files; the store is the source of truth.

Agent‑level capability facts come from OpenAPI. The `openapi-to-facts` tool (`Packages/FountainTooling/Sources/openapi-to-facts/main.swift`) reads a spec, derives a property‑exchange facts document, and optionally seeds it into the `agent-facts` collection in FountainStore. The mapping from specs to `agentId`s is maintained in `Tools/openapi-facts-mapping.json`. `Scripts/openapi/openapi-to-facts.sh` iterates this mapping, builds `openapi-to-facts`, and seeds facts for each agent. `midi-instrument-host` then reads these facts and turns them into MIDI‑CI PE properties backed by HTTP routes or other transports.

---

## 5. Instruments, Instrument Lint, and Instrument Index

Instruments are interactive applications registered in `Tools/instruments.json`. Each entry contains at least `appId`, `agentId`, `corpusId`, `spec` (under `openapi/v1`), and optional runtime agent id, test module path, snapshot baselines directory, and a list of required test symbols. For example, `llm-chat` and `fountain-gui-demo` are defined here with their tests under `Packages/FountainApps/Tests`.

`instrument-lint` (`Packages/FountainTooling/Sources/instrument-lint/main.swift`) enforces that this index is coherent: referenced specs exist, `agentId` appears in the OpenAPI‑to‑facts script, facts exist in FountainStore, test modules and baselines are present with Swift sources, and required test symbols are found. The Instrument Lint HTTP service is defined by `openapi/v1/instrument-lint.yml` and implemented on top of the same logic, so an LLM can list instruments and run lint via Tools Factory.

---

## 6. Instrument-New: Automating Instrument Scaffolding

`instrument-new` is the primary tool for adding instruments that comply with all of the above. Its core implementation is `InstrumentNew` in `Packages/FountainTooling/Sources/InstrumentNewCore/InstrumentNewCore.swift`. The configuration includes `appId`, `agentId`, `specName`, and flags (`visual`, `metalView`, `noApp`). The method `InstrumentNew.generate(in:config:dryRun:)` (1) creates the spec stub under `openapi/v1`, (2) updates `Tools/openapi-facts-mapping.json`, (3) appends an entry to `Tools/instruments.json`, (4) scaffolds a seeder under `Packages/FountainApps/Sources/<appId>-seed`, (5) creates a test module under `Packages/FountainApps/Tests/<AppId>Tests` and optional FCIS-VRT Render baselines, and (6) optionally scaffolds an FGK‑based app surface under `Packages/FountainApps/Sources/<appId>-app`. It can be invoked via the CLI (`Packages/FountainTooling/Sources/instrument-new/main.swift`) or tests (`InstrumentNewTests`).

The same behaviour is exposed as an HTTP service defined by `openapi/v1/instrument-new.yml`. `Packages/FountainTooling/Sources/InstrumentNewService` contains `openapi.yaml` + `openapi-generator-config.yaml` and `OpenAPIHandlers.swift` (`InstrumentNewOpenAPI`), which turns an `InstrumentNewRequest` into an `InstrumentNew.Config` and returns an `InstrumentNewResponse` summarizing which steps were applied. `InstrumentNewServiceKernel.swift` registers this handler on `NIOOpenAPIServerTransport`; `Packages/FountainTooling/Sources/instrument-new-service-server/main.swift` hosts it on a configurable port. `Scripts/openapi/register-instrument-new-as-tools.sh` registers this spec with Tools Factory so the `runInstrumentNew` operation becomes a tool.

---

## 7. LLM Usage Pattern

With the services running (via scripts under `Scripts/dev/`), an LLM that has HTTP access to Tools Factory works as follows. It calls `/tools` to discover available tools. It can run `instrument-lint` to understand the current instrument catalog, and `runInstrumentNew` to propose and apply instrument scaffolding, either in `dryRun` mode (plan only) or with writes enabled. After scaffolding, it can trigger `openapi-to-facts` and `instrument-lint` again to make sure agent facts and the instrument index are consistent. All of these operations are defined in OpenAPI, backed by generator‑driven Swift handlers, and validated by focused tests in `Packages/FountainTooling/Tests` and service kits.

The key point is that FountainAI offers a narrow, spec‑first surface to LLMs: specs and generator config define what exists, Tools Factory exposes those operations as tools, FountainStore holds prompts and facts, and tools like `instrument-new` and `instrument-lint` keep instruments aligned with those rules.
