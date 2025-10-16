# Gateway OpenAPI Generator Expansion Plan

Purpose: Expand Swift OpenAPI Generator coverage for the Fountain Gateway so that curated specs drive both control-plane and plugin surfaces end-to-end.

## Milestone A — Spec Alignment & Configuration
- [x] Inventory existing gateway specs (`openapi/v1/gateway.yml`, plugin specs) and confirm missing operations in generator filters. _(2025-10-16 — ChatKit routes were absent from the generator scope.)_
- [x] Update `openapi/v1/gateway.yml` (and per-plugin specs) to reflect latest request/response models, annotating auth, pagination, and upload/download behaviors. _(ChatKit session, thread, and attachment flows now document security, size limits, and SSE/tool event metadata.)_
- [x] Run `openapi/lint-matrix.sh gateway` to ensure specs pass Redocly linting.
- [x] Review `Packages/FountainSpecCuration/openapi/README.md` tables and update status entries once specs are refreshed.
- [x] Add or adjust `openapi-generator-config.yaml` filter paths in `Packages/FountainApps/Sources/GatewayServer` so ChatKit and plugin endpoints generate alongside control-plane routes.

## Milestone B — Generated Server Adoption
- [x] Run `swift build --product gateway-server` to regenerate server interfaces and surface compile errors introduced by broader generation.
  - _2025-10-17 — Blocked in local workspace because `External/Teatro/Packages/TeatroGUI` is absent. The build invocation fails before generation. Track down the missing checkout (or provide a temporary shim package) so the generator can run._
  - _2025-10-18 — Added lightweight Teatro shims under `External/Teatro` so the workspace can resolve local dependencies while the upstream repository remains unavailable._
  - _2025-10-18 — `swift build --product gateway-server` now runs the generator but fails on existing ChatKit compile errors: `ChatKitThreadMessage` lacks an `Equatable` implementation, `ChatKitGatewayPlugin` route switch still uses tuple pattern `let` bindings, and `extractToolCalls` references an `object` symbol that no longer exists. Address these before the next build attempt._
  - _2025-10-18 — Re-ran the build after addressing the ChatKit compile errors; `gateway-server` now builds cleanly with generated surfaces in place._
- [x] Replace manual router shims with generated handler conformances within `GatewayOpenAPI` to delegate to plugin kernels.
  - _2025-10-18 — Generated ChatKit handlers now consume the plugin’s `ChatKitGeneratedHandlers` typed interface, routing session, messaging, thread, and attachment flows through shared kernels without manual HTTP shims._
- [ ] Expose plugin routers as typed handler implementations by conforming to generated protocols and wiring them through the gateway dependency container.
  - _Needs design once kernels are surfaced; consider adding a `GatewayPluginRegistry` API on `GatewayServer` so handlers can look up shared plugin state instead of rebuilding stores._
  - _Pending — Access control cleanup above is prerequisite: handlers must depend only on generated request/response types rather than the plugin's internal helper structs._
- [ ] Remove redundant manual request decoding/encoding paths after generated handlers cover all operations; ensure legacy middleware (auth, rate limits) wraps new transports.
  - _Pending once generated handlers land. Confirm that middleware ordering survives (`prepare/respond`) once manual ChatKit router removal happens._
- [ ] Expand `GatewayServerTests` to cover generated ChatKit/plugin operations, asserting serialization fidelity and middleware integration.
  - _Requires in-memory attachment fixtures once upload/download handlers are rewritten. Establish fakes for `ChatKitUploadStore` so tests stay hermetic._

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
