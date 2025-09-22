# FountainKit Refactor — Agent Guide

Welcome to FountainKit, the modular SwiftPM workspace for the Fountain Coach organization (Contexter). The repository is split into local packages under `Packages/`:

- `FountainCore`: Runtime primitives, store client, adapters, launcher signature, resource helpers.
- `FountainAPIClients`: Generated OpenAPI clients and Tutor Dashboard models built on `FountainCore`.
- `FountainGatewayKit`: Gateway persona orchestrator, security/budget plugins, publishing frontend, and shared gateway utilities.
- `FountainServiceKit-<Service>`: Service libraries (planner, function-caller, bootstrap, awareness, persist, tools factory, tool server) with their helpers.
- `FountainTelemetryKit`: MIDI 2.0 streaming stack (`MIDI2*`, `SSEOverMIDI`, `FlexBridge`, `flexctl`) and related diagnostics.
- `FountainTooling`: OpenAPI curator CLI/service, client generators, SSE diagnostics, GUI tooling.
- `FountainApps`: Executable entry points (servers, CLIs, macOS launchers) that stitch the kits together.
- `FountainSpecCuration`: OpenAPI specs, fixtures, and regeneration scripts shared across packages.
- `FountainExamples`: Sample apps and Teatro integrations that consume the published packages.

## Coding standards
- Target Swift 6.1; mark public APIs as `Sendable` when feasible.
- Use dependency injection across package seams—libraries must not reach into executable-only code.
- Do not duplicate shared types; if code is reused by multiple packages, move it into `FountainCore` (or another shared kit) and document the dependency.
- Keep OpenAPI documents authoritative for every HTTP surface; update specs and regenerate clients before merging.

## Workflow
1. `swift build` at the repository root bootstraps all local packages.
2. Run focused tests with `swift test --package-path Packages/<PackageName>`; every touched package must have green tests before PRs merge.
3. Update `Package.swift` in each package whenever you add/remove targets or products; keep dependency declarations sorted alphabetically.
4. Regenerate OpenAPI clients via `swift run --package-path Packages/FountainTooling openapi-curator-cli …` and commit both specs and generated sources.
5. For telemetry changes, run `swift test --package-path Packages/FountainTelemetryKit` to cover MIDI/SSE regressions.

## Review checklist
- Builds succeed (`swift build`) and all affected package tests pass.
- No cross-package `@testable import`.
- Public APIs carry doc comments including threading and capability expectations.
- Gateway/service packages reference OpenAPI specs and configuration strictly through `FountainCore` abstractions.
- Executables in `FountainApps` import only the kits they need.

Thank you for helping FountainKit stay modular and healthy!
