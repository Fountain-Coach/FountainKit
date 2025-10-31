## PatchBay Service — Agent Guide

PatchBay persists and serves instrument graphs over HTTP. Nodes are MIDI 2.0 instruments with Property Exchange schemas; links are typed mappings (property↔property and UMP→property). The service writes graphs to FountainStore, maintains vendor identity in SecretStore, and emits AI‑readable corpus snapshots for downstream tools.

Why: keep instrument modeling behind one OpenAPI contract so the service and PatchBay app stay in lock‑step, suggestions/links are fully typed, and artifacts are deterministic (ETags) for reproducible sessions.

What/How
- Build: `swift build --package-path Packages/FountainApps -c debug --target patchbay-service`
- Run: `swift run --package-path Packages/FountainApps patchbay-service-server` (binds `PATCHBAY_PORT`/`PORT`, default 7090; falls back to an ephemeral port and prints it)
- Health: `GET /health` (used by `bash Scripts/dev-up --check`); one‑shot bind+exit via `PATCHBAY_ONESHOT=1`
- Config: `FOUNTAINSTORE_DIR` (default `.fountain/store`), `PATCHBAY_CORPUS` (default `patchbay`), SecretStore service `FountainAI.PatchBay` key `VendorIdentity` (manufacturerId/family/model/revision)

Spec (OpenAPI‑first)
`Packages/FountainApps/Sources/patchbay-service/openapi.yaml` mirrors the curated source of truth `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`. Update the curated spec first, then build to regenerate server types via the generator plugin. Generator config: `Packages/FountainApps/Sources/patchbay-service/openapi-generator-config.yaml` (`generate: [types, server]`). The app client spec lives at `Packages/FountainApps/Sources/patchbay-app/openapi.yaml`.

Keep all instruments in one document—extend `InstrumentKind`, geometry, or `PropertySchema` rather than adding per‑instrument specs. Check enum drift via `Scripts/ci/check-patchbay-spec-sync.sh`.

Routes (OpenAPI)
- Canvas: `/canvas`, `/canvas/zoom`, `/canvas/pan`
- Instruments: `/instruments` (CRUD), `/instruments/{id}/schema`
- Links: `/links` (CRUD; property↔property and UMP→property)
- Discovery: `/ci/endpoints`, `/ci/endpoints/{id}/schema`
- Suggestions: `/graph/suggest` (CI/PE‑grounded)
- Import/Export: `/graph`, `/export/json`, `/export/dsl`, `/import/json`, `/import/dsl`
- Store: `/store/graphs`, `/store/graphs/{id}` (persist `GraphDoc` as `patchbay.graphs`)
- Corpus: `/corpus/snapshot`
- Admin: `/admin/vendor-identity` (GET/PUT), `/admin/vendor-identity/allocations` (GET/POST)

Operator UX
Present one readiness verdict in a three‑pane layout, producing deterministic artifacts (ETags). Suggestions and link edits are typed end‑to‑end so actions remain explainable.

Teatro Integration
Use Teatro storyboard and MIDI 2.0 DSLs for previews, exports, and CI snapshots (see `External/TeatroPromptFieldGuide/README.md`).
- Storyboard: map canvas states to Teatro storyboard scenes; render animated SVG via `External/TeatroFull`.
- MIDI: derive a `MIDISequence` from instrument timing/link activity; play via `TeatroPlayerView`.
- Import: accept storyboard text via `/import/dsl` to seed graphs (convenience only; not canonical).
- CI: generate a storyboard from a seeded graph and compare frames to baselines (`Scripts/ci/ui-snap.sh`).

Add an Instrument (spec‑first)
Edit the curated spec, regenerate, seed defaults, and verify—keeping the app in sync and tests green.
- Curated spec: edit `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`; extend `components.schemas.InstrumentKind.enum` (e.g., `mvk.scope`, `audiotalk.chat`); add/extend `components.schemas.PropertySchema` (name, type, min/max/step/default; include aliases when renaming).
- Regenerate/build: `swift build --package-path Packages/FountainApps -c debug --target patchbay-service` regenerates server types from `openapi.yaml` (do not hand‑edit generated Swift).
- Seed/back data: set defaults in `Packages/FountainApps/Sources/patchbay-service/Handlers.swift` (constructor of `PatchBayCore`); otherwise expose via `/instruments` CRUD (POST → `CreateInstrument`). For UMP ports, set `identity.hasUMPInput/hasUMPOutput`.
- Verify endpoints: `GET /instruments` shows your kind; `GET /instruments/{id}/schema` matches your `PropertySchema`. Quick check: `curl -s http://127.0.0.1:7090/instruments | rg '<your-kind>'`.
- Keep the app in sync: mirror curated edits in `Packages/FountainApps/Sources/patchbay-app/openapi.yaml`; build `swift build --package-path Packages/FountainApps -c debug --target patchbay-app`. Instruments render automatically; add icons/preview actions under `Packages/FountainApps/Sources/patchbay-app/**` as needed.
- Tests/CI: add a seeding test under `Packages/FountainApps/Tests/PatchBayServiceTests`; update snapshot goldens under `Packages/FountainApps/Tests/PatchBayAppUITests/Baselines`; rebaseline visuals via `Scripts/ci/ui-rebaseline.sh`; enum sync via `bash Scripts/ci/check-patchbay-spec-sync.sh`.
- Local/control plane: `swift run --package-path Packages/FountainApps patchbay-service-server` or `bash Scripts/dev-up --check` to boot and probe `/health`.

Where
- Service spec: `Packages/FountainApps/Sources/patchbay-service/openapi.yaml`
- Curated spec: `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`
- Generator config: `Packages/FountainApps/Sources/patchbay-service/openapi-generator-config.yaml`
- Handlers: `Packages/FountainApps/Sources/patchbay-service/Handlers.swift`
- Instrument modules: `Packages/FountainApps/Sources/patchbay-service/InstrumentModules.swift`
- Bootstrap: `Packages/FountainApps/Sources/patchbay-service/ServerBootstrap.swift`
- App spec: `Packages/FountainApps/Sources/patchbay-app/openapi.yaml`
- Enum drift check: `Scripts/ci/check-patchbay-spec-sync.sh`
- UI baselines: `Packages/FountainApps/Tests/PatchBayAppUITests/Baselines`
