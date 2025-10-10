# FountainKit OpenAPI-First Adoption Plan — Audit 2025-10-10

_Audit date: 2025-10-10 (UTC)_  
_Git HEAD at audit: d39b3acf9f0af8b709d2f2a3a28690960b011e4e_

This audit reconciles the historical plan with the current repository state so follow-up work can focus on remaining gaps. The intent is to keep the plan actionable, highlight completed milestones with their supporting commits, and embed the most recent coverage report for future reference.

## Status summary

### Completed milestones / deliverables
- **Milestone 0 — Baseline & ownership inventory** ✅: Service ownership and spec index live in [`Packages/FountainSpecCuration/openapi/README.md`](Packages/FountainSpecCuration/openapi/README.md), satisfying the catalog requirement introduced during the initial workspace import (`04ccd0c`) and reinforced by subsequent persona updates (`ce54159`).
- **Milestone 1 — Generator bootstrap** ✅: Core packages depend on Apple's Swift OpenAPI toolchain, with plugin declarations active in `FountainServiceKit-Persist`, `FountainServiceKit-Planner`, `FountainServiceKit-SemanticBrowser`, `FountainAPIClients`, and the gateway server target (`15dbdc3`, `4d41c12`, `847d83c`, `7bd6464`).
- **Milestone 2 — Semantic Browser pilot** ✅: The Semantic Browser service and client consume generated types via `NIOOpenAPIServerTransport` and URLSession transport (`4d41c12`, `8b344d5`, `d4db71c`).
- **Gateway control-plane adoption** ✅: Gateway server routes now flow through generated handlers, backed by integration coverage and runtime wiring (`847d83c`, `422848c`, `4d3a828`, `8f392b7`, `d39b3ac`).
- **Semantic Browser packaging** ✅: `semantic-browser-server` split into standalone package `FountainApps-SemanticBrowser` to decouple Apps test graph from CNIO dependencies (`5bb7403`, `5a9c3fc`, `230d71f`).
- **Gateway tokens + framing** ✅: Fixed `/auth/token` date decoding (ISO8601) and ensured Content-Length for non-chunked responses; Gateway tests are fully green (`a1a72a4`, `487c853`).

### In-progress / outstanding focus areas
- **Milestone 3 — Generated clients beyond Persist & Semantic Browser**: `GatewayAPI` now generates types+client; `LLMGatewayAPI` remains hand-authored pending adapter updates; other curated clients still to migrate.
- **Milestone 4 — Service kit migrations**: Persist, Planner, and Semantic Browser servers are generated, but Bootstrap, Function Caller, Awareness, Tools Factory, and Tool Server still require generator adoption.
- **Milestone 5 — Gateway plugins**: Plugin surfaces retain manual handlers; specs exist but generated routing has not been introduced.
- **Milestone 6 — CI + linting**: No automated spec lint or generation verification is wired into CI yet.
- **Milestone 7 — Legacy codegen retirement**: Custom `FountainCodex` tooling persists and must be deprecated after the generator rollout completes.

## Updated milestone roadmap

### Milestone 3 — Generated clients package (partial)
- Finish migrating `GatewayAPI`, `LLMGatewayAPI`, DNS, and future clients to generated transports.
- Introduce a `FountainCore` client factory to standardise headers and base URLs for all generated clients.
- Deprecate and eventually remove the bespoke REST client once all call sites migrate.

### Milestone 4 — Service server migrations (ongoing)
- Bootstrap, Function Caller, Awareness, Tools Factory, and Tool Server kits need symlinked specs, generator configs, plugin/runtime dependencies, and handler rewrites that wrap existing logic.
- Maintain `/metrics`, `/health`, `/ready` manually until each migration stabilises.

### Milestone 5 — Gateway control plane + plugins (ongoing)
- Extend generated handler adoption to plugin routers, ensuring each plugin spec is backed by generated routing.
- Confirm security/budget hooks remain intact while delegating request parsing to generated types.

### Milestone 6 — CI, lint, and docs (not started)
- Add `Scripts/openapi-lint.sh` (or equivalent) to CI and ensure `swift build` fails when generator configs are missing.
- Update onboarding/documents so reviewers enforce the OpenAPI-first checklist.

### Milestone 7 — Retire legacy codegen (not started)
- Delete `FountainCore/FountainCodex` and related tooling once all services and clients generate from curated specs.
- Update documentation to reference only Apple's generator workflow.

## Immediate next steps
1. Finalise client migrations: complete `LLMGatewayAPI` generation (coordinate adapter updates) and assess `dns.yml` for a client target.
2. Schedule service-kit migrations starting with Bootstrap and Function Caller to reduce manual schema drift.
3. Draft CI linting tasks that validate spec + generator parity before deprecating legacy codegen.
4. Keep adoption coverage tables (`Packages/FountainSpecCuration/openapi/README.md` and `Packages/FountainSpecCuration/OPENAPI_COVERAGE.md`) up to date as targets adopt the generator.

## Appendix A: OpenAPI Generator Coverage Report
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
  - On the client side, `PersistAPI`, `SemanticBrowserAPI`, and `GatewayAPI` targets generate URLSession-based clients.

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
