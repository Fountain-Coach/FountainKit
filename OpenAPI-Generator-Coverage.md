# OpenAPI Generator Coverage Report

_Date: 2025-10-10 (UTC)_
_Git HEAD: d39b3acf9f0af8b709d2f2a3a28690960b011e4e ("e2e(gateway): add HTTP-level test for metrics auth with token issuance")_

## Coverage overview
- The curated catalog enumerates gateway plugins, planner and persistence services, core bootstrap/function-caller services, plus tools-factory/tool-server surfaces in [`Packages/FountainSpecCuration/openapi/README.md`](Packages/FountainSpecCuration/openapi/README.md).
- Only a subset of those specs currently have Swift Package targets wired to Apple's `OpenAPIGenerator` plugin:
  - `PersistService` server target in `FountainServiceKit-Persist` pulls in the generator plug-in and runtime.
  - `PlannerService` server target in `FountainServiceKit-Planner` is configured for code generation.
  - `SemanticBrowserService` server target uses the generator stack as well.
  - The `gateway-server` executable filters a limited set of admin routes through generated handlers.
  - On the client side, only `PersistAPI` and `SemanticBrowserAPI` targets generate URLSession-based clients.

## Gaps and forgotten surfaces
- Most curated specs—`bootstrap`, `baseline-awareness`, `function-caller`, `dns`, `tools-factory`, `tool-server`, the OpenAPI curator service, and every gateway plugin spec—lack Swift targets that reference the generator plug-in.
- Gateway-facing client libraries (`GatewayAPI`, `LLMGatewayAPI`) are hand-authored and depend solely on shared client utilities, with no generator support.
- The Tool Server package only ships `openapi.yaml` as a resource, leaving handlers and clients to be maintained manually.
- Without generator wiring, specs and implementations risk drifting apart, forcing manual upkeep of request/response shapes.

## Recommended next steps
1. For each spec missing generated bindings, add an `openapi.yaml` (or curated symlink) plus `openapi-generator-config.yaml` to the appropriate target directory, then declare the generator plug-in and runtime dependencies in `Package.swift`, following the patterns in Persist, Planner, SemanticBrowser, and Gateway server targets.
2. Prioritise high-traffic surfaces—Function Caller, Bootstrap, and gateway plugins—to reduce manual stubs and keep curated contracts authoritative.
3. Continue updating specs first, linting via `Scripts/openapi-lint.sh`, and run `swift build` to regenerate bindings so source and schema stay aligned.

## Git history reference
- Report captured against repository state `d39b3acf9f0af8b709d2f2a3a28690960b011e4e` (see `git show d39b3acf9f0af8b709d2f2a3a28690960b011e4e`).
