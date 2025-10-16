# OpenAPI Generator Coverage Report

_Date: 2025-10-20 (UTC)_
_Git HEAD: work ("Milestone D — CI & tooling updates")_

## Coverage overview
- The curated catalog enumerates gateway plugins, planner and persistence services, core bootstrap/function-caller services, plus tools-factory/tool-server surfaces in [`Packages/FountainSpecCuration/openapi/README.md`](Packages/FountainSpecCuration/openapi/README.md).
- Generator adoption now spans the highest-traffic surfaces:
  - `gateway-server` builds its entire control plane **and** ChatKit plugin flows from the curated specs. CI now runs `swift build --explicit-target-dependency-import-check` at the workspace root on macOS and Linux, guaranteeing the generator executes on every push.
  - `Packages/FountainApps/Sources/gateway-ci-smoke` provides a CLI harness that exercises ChatKit session creation, refresh, messaging, thread listing, fetch, and deletion via the generated `GatewayAPI.Client` while core services run under `Scripts/ci-smoke.sh`.
  - `PersistService`, `PlannerService`, and `SemanticBrowserService` server targets continue to ship generated handlers.
  - Client-side, `GatewayAPI`, `PersistAPI`, `SemanticBrowserAPI`, and `LLMGatewayAPI` deliver URLSession and AsyncHTTPClient transports backed by generated types.

## Gaps and forgotten surfaces
- Most curated specs—`bootstrap`, `baseline-awareness`, `function-caller`, `dns`, `tools-factory`, `tool-server`, and the OpenAPI curator service—still need Swift targets that reference the generator plug-in.
- Gateway plugins beyond ChatKit continue to expose manual kernels; extend typed handler adoption to achieve parity.
- The Tool Server package only ships `openapi.yaml` as a resource, leaving handlers and clients to be maintained manually.
- Without generator wiring, specs and implementations risk drifting apart, forcing manual upkeep of request/response shapes.

## Recommended next steps
1. For each spec missing generated bindings, add an `openapi.yaml` (or curated symlink) plus `openapi-generator-config.yaml` to the appropriate target directory, then declare the generator plug-in and runtime dependencies in `Package.swift`, following the patterns in Persist, Planner, SemanticBrowser, and Gateway server targets.
2. Prioritise high-traffic surfaces—Function Caller, Bootstrap, and gateway plugins—to reduce manual stubs and keep curated contracts authoritative.
3. Continue updating specs first, linting via `Scripts/openapi-lint.sh`, and run `swift build` (mirroring the new CI job) to regenerate bindings so source and schema stay aligned.

## Git history reference
- Report captured against repository state `work` (`Milestone D — CI & tooling updates`).
