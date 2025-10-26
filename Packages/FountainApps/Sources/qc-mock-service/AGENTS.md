## AGENT — qc‑mock‑service (OpenAPI‑first)

qc‑mock‑service is the HTTP source of truth for the QC Mock canvas editor; the app must conform to it, and other tools integrate via this API. Code lives under `Packages/FountainApps/Sources/qc-mock-service/**`.

Spec and generation
The curated, canonical spec is `Packages/FountainSpecCuration/openapi/v1/qc-mock.yaml`. The generator reads a local copy at `Sources/qc-mock-service/openapi.yaml` with its config at `Sources/qc-mock-service/openapi-generator-config.yaml`. Update the curated spec first, then regenerate by building: `swift build --package-path Packages/FountainApps -c debug --target qc-mock-service`. Implement handlers to satisfy generated server protocols (TDD).

Endpoints
Canvas state is managed via `GET/PATCH /canvas` plus `POST /canvas/zoom*` and `POST /canvas/pan`. Graph operations cover nodes/ports/edges CRUD (`/nodes`, `/edges`) and export/import (JSON & DSL). Health is `GET /health`.

Design rules
There is one transform: a doc→view mapping (`CanvasTransform`) from QCMockCore — the service manipulates this state and composes deterministic rules; snap/decimation remain QCMockCore responsibilities. The service has no UI; only state and pure transforms.

Testing
Add tests per operation (request→effect→response). Server handlers must call into QCMockCore for math/graph ops; avoid hand‑coded responses without tests. Quick commands: generate/build types with `swift build --package-path Packages/FountainApps -c debug --target qc-mock-service`; core math tests via `swift run --package-path Packages/FountainApps qcmockcore-tests`; handler tests via `swift run --package-path Packages/FountainApps qc-mock-handlers-tests`.

Notes
Keep the local `openapi.yaml` in sync with the curated spec until we switch to a symlink or plugin parameter. Ensure path params exist on nested paths (e.g., both `/nodes/{id}/ports` and `/nodes/{id}/ports/{portId}` declare `id`).
