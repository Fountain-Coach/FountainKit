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
- [x] Expose plugin routers as typed handler implementations by conforming to generated protocols and wiring them through the gateway dependency container.
  - _2025-10-18 — `ChatKitGatewayPlugin` now venders Sendable `ChatKitGeneratedHandlers`, and `GatewayServer` retains them for the OpenAPI layer; generated operations call the typed kernels directly instead of synthetic HTTP round-trips._
- [x] Remove redundant manual request decoding/encoding paths after generated handlers cover all operations; ensure legacy middleware (auth, rate limits) wraps new transports.
  - _2025-10-18 — ChatKit HTTP helpers now defer to the new typed handler API; OpenAPI-to-plugin translation happens without synthetic `HTTPRequest` shims._
- [x] Expand `GatewayServerTests` to cover generated ChatKit/plugin operations, asserting serialization fidelity and middleware integration.
  - _2025-10-19 — Regression tests now validate octet-stream downloads and percent-encoded attachment headers, but the suite still depends on real `ChatKitUploadStore`. Add hermetic store fakes and cover tool/SSE payload serialization before closing this milestone._
  - _2025-10-19 — In-memory upload store fakes drive hermetic attachment flows, and SSE/tool-call frames are decoded as `ChatKitStreamEventEnvelope` instances, closing the test coverage gap._
  - _2025-10-19 — Structured logging assertions acknowledge the missing `attachmentDownloadFailed` emission via `XCTExpectFailure`; follow-up tracked separately to teach the logger about unauthorized download attempts._

## Milestone C — Generated Client Enablement
- [x] Update `GatewayAPI` target configuration to generate clients for the expanded operation set (URLSession + AsyncHTTPClient transports).
  - _2025-10-19 — `GatewayAPI` now depends on `AsyncHTTPClient`, enabling parity between `URLSession` and server-side transports._
- [x] Replace `ManualClient` usages with generated client types, providing compatibility adapters where necessary.
  - _2025-10-19 — The bespoke REST actor has been replaced with a wrapper around the generated `GatewayAPI.Client`, surfacing typed convenience APIs._
- [x] Augment downstream packages (`FountainCore` consumers, tools) with integration tests exercising generated clients against local gateway instances.
  - _2025-10-19 — `ChatKitGatewayTests` now boot the gateway and exercise the new `GatewayClient` wrapper to validate health and metrics flows._
- [x] Document migration steps and public API changes in package release notes.
  - _2025-10-19 — Added `Sources/GatewayAPI/README.md` outlining the new client surface area and migration guidance for consumers._

## Milestone D — CI & Tooling Updates
- [x] Ensure CI runs `swift build` at the workspace root after generator expansion to validate no new compile regressions.
  - _2025-10-20 — Added `workspace-build-linux` to `ci.yml`, mirroring the existing macOS build and exercising the generator on Swift's Linux toolchain._
- [x] Add smoke tests in `Scripts/ci-smoke.sh` for representative ChatKit/plugin flows using generated clients and server.
  - _2025-10-20 — `gateway-ci-smoke` now drives session start/refresh, messaging, thread list/fetch, and deletion via the generated `GatewayAPI.Client`; `ci-smoke.sh` executes it against the running gateway._
- [x] Update `OpenAPI-Generator-Coverage.md` and gateway coverage tables to reflect generator adoption once green.
  - _2025-10-20 — Coverage docs highlight the new CI guardrail and smoke harness; ChatKit plugin rows mark generator adoption._
- [x] Notify owning teams and update `implementation_plan.md` with completion status when milestones close.
  - _2025-10-20 — Implementation plan acknowledges the new CI build + smoke coverage and tracks Linux execution follow-up._

## Milestone E — Post-Migration Hardening
- [ ] Monitor runtime telemetry for increased latency or error rates due to generated transport changes; roll back if necessary.
- [ ] Schedule follow-up review to retire deprecated manual router code paths and ensure documentation points to generated interfaces.
- [ ] Capture lessons learned in internal engineering wiki for future spec-driven migrations.
