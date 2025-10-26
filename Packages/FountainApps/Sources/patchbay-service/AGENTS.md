## AGENT — patchbay-service (OpenAPI‑first)

Purpose
- PatchBay — CI/PE‑first instrument sketch service. QC‑style canvas, but nodes are MIDI 2.0 instruments with PE property schemas.
- First‑class FountainAI service: persistence (FountainStore), vendor identity (SecretStore), and corpus snapshot export.

Build
- Generate + build: `swift build --package-path Packages/FountainApps -c debug --target patchbay-service`
- Run service: `swift run --package-path Packages/FountainApps patchbay-service-server`

Notes
- Spec sync: `Sources/patchbay-service/openapi.yaml` mirrors curated `Packages/FountainSpecCuration/openapi/v1/patchbay.yml` (authoritative).
- Store: uses `FountainStoreClient` with `FOUNTAINSTORE_DIR` (defaults to `.fountain/store`). Corpus id via `PATCHBAY_CORPUS` (default `patchbay`).
- Secrets: vendor identity (manufacturerId/family/model/revision) stored via `SecretStore` under service `FountainAI.PatchBay` key `VendorIdentity`.
- Endpoints
  - Canvas: `/canvas`, zoom/pan.
  - Instruments: `/instruments` CRUD, `/instruments/{id}/schema`.
  - Links: `/links` CRUD (property↔property, UMP→property).
  - Discovery: `/ci/endpoints`, `/ci/endpoints/{id}/schema` (PE snapshots).
  - Suggest: `/graph/suggest` (auto‑noodling by PE intersection).
  - Import/Export: `/graph`, `/export/json|dsl`, `/import/json|dsl`.
  - Store: `/store/graphs`, `/store/graphs/{id}` (persist GraphDoc in FountainStore as `patchbay.graphs`).
  - Corpus: `/corpus/snapshot` (AI‑readable snapshot for Tools Factory/curation).
  - Admin: `/admin/vendor-identity` GET/PUT, `/admin/vendor-identity/allocations` GET/POST (sub‑ID allocation, stored as `patchbay.allocations`).

UX Parity
- Treat PatchBay UI like AudioTalk’s operator UX: readiness verdict, three‑pane layout, deterministic exports (ETags), and clear CI/PE auto‑wiring.

