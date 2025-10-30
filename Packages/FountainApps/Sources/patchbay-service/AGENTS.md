## PatchBay Service — Agent Guide

PatchBay sketches and persists instrument graphs over HTTP. Nodes are MIDI 2.0 instruments with PE schemas; links are typed mappings (property↔property, UMP→property). As part of Fountain, it writes graphs to FountainStore, keeps vendor identity in SecretStore, and emits AI‑readable corpus snapshots for downstream tools.

Why: keep instrument modeling behind one OpenAPI contract so the service and PatchBay app stay in lock‑step, links and suggestions remain fully typed, and artifacts are deterministic (ETags) for reproducible sessions.

Run
- Build: `swift build --package-path Packages/FountainApps -c debug --target patchbay-service`
- Run: `swift run --package-path Packages/FountainApps patchbay-service-server` (binds `PATCHBAY_PORT`/`PORT`, defaults to 7090; falls back to an ephemeral port and prints it)
- Health: `GET /health` (used by `bash Scripts/dev-up --check`); one‑shot bind and exit via `PATCHBAY_ONESHOT=1`

Spec
`Packages/FountainApps/Sources/patchbay-service/openapi.yaml` mirrors the curated source of truth `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`. Update the curated spec first, then build to regenerate server types via the plugin. The generator config lives at `Packages/FountainApps/Sources/patchbay-service/openapi-generator-config.yaml` (`generate: [types, server]`). App client spec is at `Packages/FountainApps/Sources/patchbay-app/openapi.yaml`. Keep all instruments in this single document—extend `InstrumentKind`, geometry, or `PropertySchema` rather than introducing per‑instrument specs. For enum drift checks, use `Scripts/ci/check-patchbay-spec-sync.sh`.

Config
- Store: `FOUNTAINSTORE_DIR` (defaults to `.fountain/store`); corpus id `PATCHBAY_CORPUS` (defaults to `patchbay`).
- Identity: SecretStore under service `FountainAI.PatchBay`, key `VendorIdentity` (manufacturerId/family/model/revision).

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
One readiness verdict, a three‑pane layout, and deterministic artifacts (ETags). Suggestions and link edits are typed end‑to‑end so actions are explainable.

Teatro integration
Use the Teatro view/storyboard and MIDI 2.0 DSLs for previews, exports, and CI snapshots; see `External/TeatroPromptFieldGuide/README.md`.
- Storyboard: map canvas states to Teatro Storyboard scenes and render animated SVG via `External/TeatroFull`.
- MIDI: derive a `MIDISequence` from instrument timing/link activity and play via `TeatroPlayerView`.
- Import: accept storyboard text via `/import/dsl` to seed graphs (convenience only; not canonical).
- CI: generate a storyboard from a seeded graph and compare frames to baselines (`Scripts/ci/ui-snap.sh`).

Add an instrument (spec‑first)
Add new instruments without breaking the contract.
- Curated spec: edit `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`; extend `components.schemas.InstrumentKind.enum` (e.g., `mvk.scope`, `audiotalk.chat`); add/extend `components.schemas.PropertySchema` (name, type, min/max/step/default; include aliases when renaming).
- Regenerate/build: `swift build --package-path Packages/FountainApps -c debug --target patchbay-service` to regenerate server types from `openapi.yaml` (do not hand‑edit generated Swift).
- Seed/back data: for defaults, seed in `Packages/FountainApps/Sources/patchbay-service/Handlers.swift` (constructor of `PatchBayCore`); otherwise expose via `/instruments` CRUD (POST → `CreateInstrument`). For UMP ports, set `identity.hasUMPInput/hasUMPOutput`.
- Verify endpoints: `GET /instruments` returns your kind; `GET /instruments/{id}/schema` matches your `PropertySchema`. Quick check: `curl -s http://127.0.0.1:7090/instruments | rg '<your-kind>'`.
- Keep the app in sync: mirror curated edits in `Packages/FountainApps/Sources/patchbay-app/openapi.yaml`, then build the app `swift build --package-path Packages/FountainApps -c debug --target patchbay-app`. Instruments render automatically; add icons/preview actions under `Packages/FountainApps/Sources/patchbay-app/**` as needed.
- Tests/CI: add a seeding test in `Packages/FountainApps/Tests/PatchBayServiceTests`; update snapshot goldens under `Packages/FountainApps/Tests/PatchBayAppUITests/Baselines`; rebaseline visuals via `Scripts/ci/ui-rebaseline.sh`. Enum sync: `bash Scripts/ci/check-patchbay-spec-sync.sh`.
- Local/control plane: `swift run --package-path Packages/FountainApps patchbay-service-server` or `bash Scripts/dev-up --check` to boot and probe `/health`.
