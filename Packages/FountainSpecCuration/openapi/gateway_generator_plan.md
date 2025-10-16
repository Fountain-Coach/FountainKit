# Gateway OpenAPI Generator Expansion Plan

Purpose: Expand Swift OpenAPI Generator coverage for the Fountain Gateway so that curated specs drive both control-plane and plugin surfaces end-to-end.

## Milestone A — Spec Alignment & Configuration
- [ ] Inventory existing gateway specs (`openapi/v1/gateway.yml`, plugin specs) and confirm missing operations in generator filters.
- [ ] Update `openapi/v1/gateway.yml` (and per-plugin specs) to reflect latest request/response models, annotating auth, pagination, and upload/download behaviors.
- [ ] Run `openapi/lint-matrix.sh gateway` to ensure specs pass Redocly linting.
- [ ] Review `Packages/FountainSpecCuration/openapi/README.md` tables and update status entries once specs are refreshed.
- [ ] Add or adjust `openapi-generator-config.yaml` filter paths in `Packages/FountainApps/Sources/GatewayServer` so ChatKit and plugin endpoints generate alongside control-plane routes.

## Milestone B — Generated Server Adoption
- [ ] Run `swift build --product gateway-server` to regenerate server interfaces and surface compile errors introduced by broader generation.
- [ ] Replace manual router shims with generated handler conformances within `GatewayOpenAPI` to delegate to plugin kernels.
- [ ] Expose plugin routers as typed handler implementations by conforming to generated protocols and wiring them through the gateway dependency container.
- [ ] Remove redundant manual request decoding/encoding paths after generated handlers cover all operations; ensure legacy middleware (auth, rate limits) wraps new transports.
- [ ] Expand `GatewayServerTests` to cover generated ChatKit/plugin operations, asserting serialization fidelity and middleware integration.

## Milestone C — Generated Client Enablement
- [ ] Update `GatewayAPI` target configuration to generate clients for the expanded operation set (URLSession + AsyncHTTPClient transports).
- [ ] Replace `ManualClient` usages with generated client types, providing compatibility adapters where necessary.
- [ ] Augment downstream packages (`FountainCore` consumers, tools) with integration tests exercising generated clients against local gateway instances.
- [ ] Document migration steps and public API changes in package release notes.

## Milestone D — CI & Tooling Updates
- [ ] Ensure CI runs `swift build` at the workspace root after generator expansion to validate no new compile regressions.
- [ ] Add smoke tests in `Scripts/ci-smoke.sh` for representative ChatKit/plugin flows using generated clients and server.
- [ ] Update `OpenAPI-Generator-Coverage.md` and gateway coverage tables to reflect generator adoption once green.
- [ ] Notify owning teams and update `implementation_plan.md` with completion status when milestones close.

## Milestone E — Post-Migration Hardening
- [ ] Monitor runtime telemetry for increased latency or error rates due to generated transport changes; roll back if necessary.
- [ ] Schedule follow-up review to retire deprecated manual router code paths and ensure documentation points to generated interfaces.
- [ ] Capture lessons learned in internal engineering wiki for future spec-driven migrations.
