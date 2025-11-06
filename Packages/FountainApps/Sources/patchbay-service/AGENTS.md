## PatchBay Service — Agent Guide

PatchBay persists and serves instrument graphs over HTTP. Nodes are MIDI 2.0 instruments with Property Exchange schemas; links are typed mappings (property↔property and UMP→property). The service writes graphs to FountainStore, maintains vendor identity in SecretStore, and emits AI‑readable corpus snapshots for downstream tools.

**What**
PatchBay Service is the OpenAPI‑backed server for PatchBay graphs. It exposes canvas, instrument, and link operations; persists deterministic artifacts (ETags) in FountainStore; and keeps the PatchBay app in lock‑step via a shared spec and generated types.

**Why**
Keep instrument modeling behind one contract so the app and service evolve together, suggestions/links stay fully typed end‑to‑end, and sessions are reproducible via ETags.

**How**
- Build server target: `swift build --package-path Packages/FountainApps -c debug --target patchbay-service`
- Run server: `swift run --package-path Packages/FountainApps patchbay-service-server` (binds `PATCHBAY_PORT`/`PORT`, default 7090; falls back to an ephemeral port and prints it)
- Health probe: `GET /health` (used by `Scripts/dev-up --check`); one‑shot bind+exit with `PATCHBAY_ONESHOT=1`
- Config: `FOUNTAINSTORE_DIR` (default `.fountain/store`), `PATCHBAY_CORPUS` (default `patchbay`), SecretStore service `FountainAI.PatchBay` key `VendorIdentity` (manufacturerId/family/model/revision)
- Spec first: edit `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`; mirror at `Packages/FountainApps/Sources/patchbay-service/openapi.yaml`; generator config `Packages/FountainApps/Sources/patchbay-service/openapi-generator-config.yaml` (`generate: [types, server]`). App client spec: `Packages/FountainApps/Sources/patchbay-app/openapi.yaml`.
- PB‑VRT doc (Vision+Audio): corpus `patchbay`, page `docs:pb-vrt-vision-audio`, segment `doc`. Fetch: `CORPUS_ID=patchbay SEGMENT_ID='docs:pb-vrt-vision-audio:doc' swift run --package-path Packages/FountainApps store-dump`.
- One spec for all instruments: extend `InstrumentKind`, geometry, or `PropertySchema` rather than adding per‑instrument specs. Enum drift check: `Scripts/ci/check-patchbay-spec-sync.sh`.

**Routes (OpenAPI)**
- Canvas: `/canvas`, `/canvas/zoom`, `/canvas/pan`
- Instruments: `/instruments` (CRUD), `/instruments/{id}/schema`
- Links: `/links` (CRUD; property↔property and UMP→property)
- Discovery: `/ci/endpoints`, `/ci/endpoints/{id}/schema`
- Suggestions: `/graph/suggest` (CI/PE‑grounded)
- Import/Export: `/graph`, `/export/json`, `/export/dsl`, `/import/json`, `/import/dsl`
- Store: `/store/graphs`, `/store/graphs/{id}` (persist `GraphDoc` as `patchbay.graphs`)
- Corpus: `/corpus/snapshot`
- Admin: `/admin/vendor-identity` (GET/PUT), `/admin/vendor-identity/allocations` (GET/POST)

**Operator UX**
Present one readiness verdict (three‑pane layout), produce deterministic artifacts (ETags), and keep actions explainable with typed suggestions and link edits.

**Teatro Integration**
Use Teatro storyboard and MIDI 2.0 DSLs for previews, exports, and CI snapshots (see `External/TeatroPromptFieldGuide/README.md`). Map canvas states to storyboard scenes and render via `External/TeatroFull`; derive `MIDISequence` from instrument timing/link activity; accept storyboard text via `/import/dsl` (convenience only); compare generated storyboards to baselines with `Scripts/ci/ui-snap.sh`.

**Add an Instrument (spec‑first)**
- Curated spec: edit `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`; extend `components.schemas.InstrumentKind.enum` (e.g., `mvk.scope`, `audiotalk.chat`); add/extend `components.schemas.PropertySchema` (name, type, min/max/step/default; include aliases when renaming).
- Regenerate/build: `swift build --package-path Packages/FountainApps -c debug --target patchbay-service` regenerates server types from `openapi.yaml` (never hand‑edit generated Swift).
- Seed/back data: set defaults in `Packages/FountainApps/Sources/patchbay-service/Handlers.swift` (constructor of `PatchBayCore`); otherwise expose via `/instruments` CRUD (POST → `CreateInstrument`). For UMP ports, set `identity.hasUMPInput/hasUMPOutput`.
- Verify endpoints: `GET /instruments` shows your kind; `GET /instruments/{id}/schema` matches your `PropertySchema`. Quick check: `curl -s http://127.0.0.1:7090/instruments | rg '<your-kind>'`.
- Keep the app in sync: mirror curated edits in `Packages/FountainApps/Sources/patchbay-app/openapi.yaml`; build `swift build --package-path Packages/FountainApps -c debug --target patchbay-app`. Instruments render automatically; add icons/preview actions under `Packages/FountainApps/Sources/patchbay-app/**` as needed.
- Tests/CI: add a seeding test under `Packages/FountainApps/Tests/PatchBayServiceTests`; update snapshot goldens under `Packages/FountainApps/Tests/PatchBayAppUITests/Baselines`; rebaseline with `Scripts/ci/ui-rebaseline.sh`; keep enums in sync with `bash Scripts/ci/check-patchbay-spec-sync.sh`.
- Local/control plane: `swift run --package-path Packages/FountainApps patchbay-service-server` or `bash Scripts/dev-up --check` to boot and probe `/health`.

**Where**
- Service spec: `Packages/FountainApps/Sources/patchbay-service/openapi.yaml`
- Curated spec: `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`
- Generator config: `Packages/FountainApps/Sources/patchbay-service/openapi-generator-config.yaml`
- Handlers: `Packages/FountainApps/Sources/patchbay-service/Handlers.swift`
- Instrument modules: `Packages/FountainApps/Sources/patchbay-service/InstrumentModules.swift`
- Bootstrap: `Packages/FountainApps/Sources/patchbay-service/ServerBootstrap.swift`
- App spec: `Packages/FountainApps/Sources/patchbay-app/openapi.yaml`
- Enum drift check: `Scripts/ci/check-patchbay-spec-sync.sh`
- UI baselines: `Packages/FountainApps/Tests/PatchBayAppUITests/Baselines`
