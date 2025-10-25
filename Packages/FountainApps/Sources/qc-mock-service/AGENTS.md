## AGENT — qc-mock-service (OpenAPI‑first)

Scope
- Path: `Packages/FountainApps/Sources/qc-mock-service/**`.
- Purpose: HTTP service for the QC Mock canvas editor. This service is the source of truth; the app must conform to it. FountainAI and other tools integrate via this API.

Source of truth
- Canonical spec (curated): `Packages/FountainSpecCuration/openapi/v1/qc-mock.yaml`.
- Generator input (local copy for plugin): `Sources/qc-mock-service/openapi.yaml` (kept in sync with curated spec).
- Generator config: `Sources/qc-mock-service/openapi-generator-config.yaml`.

OpenAPI workflow (required)
1) Update the spec first (endpoints/schemas).
2) `swift build --package-path Packages/FountainApps -c debug --target qc-mock-service` regenerates types/server stubs.
3) Implement handlers to satisfy the generated server protocols (TDD).

Endpoints (summary)
- Canvas: GET/PATCH `/canvas`, POST `/canvas/zoom*`, POST `/canvas/pan`.
- Graph: nodes/ports/edges CRUD (`/nodes`, `/edges`), export/import JSON & DSL.
- Health: GET `/health`.

Design rules
- One transform: doc→view mapping from QCMockCore (CanvasTransform); server manipulates this state.
- Snap/decimation are QCMockCore responsibilities; service composes these deterministic rules.
- No UI in the service; only state and pure transforms.

TDD
- Add tests for each operation (request→effect→response).
- Server handlers must use QCMockCore for math and graph ops.
- No hand‑coded responses without tests.

Dev commands
- Generate + build types: `swift build --package-path Packages/FountainApps -c debug --target qc-mock-service`
- Core math tests (fast): `swift run --package-path Packages/FountainApps qcmockcore-tests`
- Service handlers self-test (fast): `swift run --package-path Packages/FountainApps qc-mock-handlers-tests`

Notes
- Keep `openapi.yaml` here in sync with the curated spec until we switch to a symlink or plugin param.

Sync detail
- Ensure path params are declared on nested paths too (e.g., `/nodes/{id}/ports` and `/nodes/{id}/ports/{portId}` include `id`).
