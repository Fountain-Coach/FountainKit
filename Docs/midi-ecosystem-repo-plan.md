# MIDI/WebGPU Backplane — Repo Split Blueprint

Purpose: carve out a dedicated repository for the MIDI 2.0 backplane, schema, generators, runtimes, and conformance tests, while FountainKit remains the consumer workspace. This isolates the “rail” (contract + timing + tooling) from historical HTTP/OpenAPI code paths and gives innovation a clean, versioned home.

## Scope (new repo)
- Canonical MIDI IDL: the single source of truth for topics, payload fields, envelope structure, QoS codes, error model, capability masks, timing budgets, and chunking semantics.
- Facts generator: `midi-schema-to-facts` that turns the IDL into tool descriptors for LLM hosts and runtime loading.
- Runtimes and bindings: shared code that enforces envelopes and clocks, with bindings for `midi2.js` and `midi2.swift` (pub/sub API, chunking, telemetry hooks). WebGPU helpers for the GPU topic set.
- Conformance: protocol fixtures, fuzzers, jitter/latency harness, GPU correctness tests, and CI gates.
- Docs: narrative specs, change logs, and migration notes; no app-specific prompts or facts.

## Boundaries
- In-repo: MIDI schema/IDL, generators, runtime bindings, telemetry spec, fixtures, conformance tests.
- Out-of-repo: application code, prompts, facts instances, and store seeders stay in FountainKit. Bridge layers that map legacy HTTP routes to MIDI topics, if needed, live in FountainKit only.
- History: do not import legacy HTTP/OpenAPI artifacts; start from a clean commit history. Everything HTTP stays in FountainKit.

## Repository layout (proposed)
- `schema/`: IDL files (human-editable JSON or YAML); versioned and review-gated.
- `tools/`
  - `midi-schema-to-facts/` (CLI + library) emitting facts for LLM tooling and hosts.
  - `midi-schema-lint/` (schema validator, envelope/QoS checks, reserved bits).
- `runtimes/`
  - `js/` (npm workspace) with the MIDI backplane core, WebGPU helpers, and test fixtures.
  - `swift/` (SwiftPM package) mirroring the contract; integrates with `midi2.swift`.
- `conformance/`: protocol vectors, chunking/gap cases, jitter benches, GPU correctness suites.
- `docs/`: spec narrative, envelope/QoS definitions, capability policy, release notes.
- `scripts/ci/`: lint, schema diff guard, conformance test runners, release tagging.

## Versioning and releases
- Semantic versioning on the IDL (major bumps for breaking topic/payload/envelope changes).
- Tag npm (js runtime) and SwiftPM (swift runtime) artifacts aligned to the IDL version.
- Facts generator emits versioned outputs; consumers pin by version.
- CI blocks releases unless schema lint, conformance, and runtime tests pass.

## Governance
- Schema changes require review plus conformance fixture updates.
- Envelope/QoS/capability semantics live in one place: schema + docs; tests must cover new codes.
- Telemetry fields are part of the contract and versioned (no ad-hoc metrics).
- No prompts or facts instances in this repo; only generators and schema.

## Integration with FountainKit
- FountainKit pulls:
  - IDL versioned artifact (for references and local validation).
  - Facts generator (as a tool dependency) to produce facts stored in FountainStore.
  - Runtime packages (`midi2.js`/`midi2.swift` bindings) for app hosts.
- Store workflow: FountainKit seeders fetch schema → run `midi-schema-to-facts` → persist facts in FountainStore → runtimes load at boot.
- Compatibility: optional bridge modules in FountainKit map selected HTTP flows to MIDI topics; they are not part of the new repo.

## Migration path (high level)
1) Land the IDL scaffold (envelope, QoS, capability masks, error codes, chunking, base topic registry) in the new repo.
2) Ship `midi-schema-to-facts` and linting tooling; add initial conformance fixtures.
3) Publish js/swift runtime bindings that enforce the envelope and topic registry, with WebGPU helpers for `gpu/*`.
4) In FountainKit, wire a seed path: fetch schema → generate facts → store → boot hosts with the new runtime.
5) Add bridge (if needed) for legacy HTTP topics, then phase it out as consumers migrate.

## Why this split works
- Clean innovation lane: MIDI/WebGPU rail evolves without HTTP baggage.
- Deterministic consumption: FountainKit treats the rail as a versioned dependency with pinned schema and facts.
- Auditability: schema, telemetry spec, and conformance live together; releases are gated.
- Safety: no secrets, prompts, or app data in the new repo; only contract and tooling.
