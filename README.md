
# FountainKit Workspace

FountainKit is the Swift Package Manager workspace that powers FountainAI for the Fountain Coach GitHub organization. It decomposes the original monolithic package into focused modules that can evolve, test, and ship independently.

## Package overview

| Package | Description |
| ------- | ----------- |
| `FountainCore` | Networking/runtime primitives, FountainStore client, launcher signature, resource utilities, and shared AI adapters. |
| `FountainAPIClients` | OpenAPI-driven REST clients and Tutor Dashboard domain models layered on `FountainCore`. |
| `FountainGatewayKit` | Persona orchestrator, gateway plugins, and publishing frontend for the control plane. |
| `FountainServiceKit-<Service>` | Service libraries for planner, function caller, bootstrap, awareness, persist, tools factory, and tool server. |
| `FountainTelemetryKit` | MIDI 2.0 streaming models, transports, and SSE/MIDI diagnostics (`flexctl`). |
| `FountainTooling` | OpenAPI curator CLI/service, client generator, SSE client, and GUI diagnostics tools. |
| `FountainApps` | Executable entry points (gateway server, service daemons, tutor dashboard CLI, macOS launcher). |
| `FountainSpecCuration` | Authoritative OpenAPI specs, fixtures, and regeneration scripts. |
| `FountainExamples` | Sample Teatro integrations and showcase applications using the modular kits. |

Each package lives under `Packages/<Name>` with its own `Package.swift`, `Sources/`, `Tests/`, and `README`. The root manifest depends on these packages via relative paths for local development.

## Getting started

### Bootstrap the workspace
```bash
swift build
```

### Run targeted tests

```bash
swift test --package-path Packages/FountainCore
swift test --package-path Packages/FountainGatewayKit
swift test --package-path Packages/FountainTelemetryKit
swift test --package-path Packages/FountainExamples
```

### Launch the gateway server (assembled from kits)

```bash
swift run --package-path Packages/FountainApps gateway-server
```

### Run cross-package examples

```bash
swift run --package-path Packages/FountainExamples hello-fountainai-teatro
```

The executable seeds an in-memory Fountain Store and routes a request through
the gateway, planner, and function-caller services, providing integration
coverage alongside the package tests.

## Development workflow

* **Pick the right package:**
  Runtime-level changes live in `FountainCore`, service logic in its `FountainServiceKit-<Service>`, telemetry work in `FountainTelemetryKit`, etc.

* **Update manifests:**
  Update the relevant `Package.swift` when adding products, dependencies, or resources.

* **Document public APIs:**
  Add docs in package READMEs and doc comments; note capability requirements and threading expectations.

* **Regenerate clients:**
  Use the `openapi-curator-cli` in `FountainTooling` whenever specs change.

* **Keep dependencies acyclic:**
  Higher-level kits may depend on `FountainCore` and peer kits, but never in reverse.

## Contributing

* Follow the engineering guide in `AGENTS.md`.
* Ensure `swift build` and package-specific `swift test` succeed before opening PRs.
* Update deployment manifests, Dockerfiles, and scripts to reference the new package paths when services move.
* Tag releases per package so downstream consumers can track API changes.

## License

FountainKit inherits the licensing terms of the original FountainAI project; consult the repository’s `LICENSES/` directory for details.


