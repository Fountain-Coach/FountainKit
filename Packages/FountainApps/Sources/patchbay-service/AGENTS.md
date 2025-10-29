## PatchBay Service — Agent Guide (OpenAPI‑first)

PatchBay sketches and persists instrument graphs over HTTP. Nodes are MIDI 2.0 instruments (with PE schemas) and links are typed mappings (property↔property, UMP→property). PatchBay is part of the Fountain stack: it writes graphs to FountainStore, keeps vendor identity in SecretStore, and emits AI‑readable corpus snapshots for downstream tools.

Why this service exists: unify instrument modeling behind one OpenAPI contract so the service and PatchBay app stay in lock‑step, keep links and suggestions fully typed, and produce deterministic artifacts (ETags) for reproducible sessions.

How to run: build with SwiftPM; the control plane uses `Scripts/dev-up` to start PatchBay. Manual runs bind to `PATCHBAY_PORT` (7090 by default) and fall back to an ephemeral port if busy, printing the bound port.

- Build: `swift build --package-path Packages/FountainApps -c debug --target patchbay-service`
- Run: `swift run --package-path Packages/FountainApps patchbay-service-server`
- Health: `GET /health` (used by `Scripts/dev-up --check`)

Where specs live: `Packages/FountainApps/Sources/patchbay-service/openapi.yaml` mirrors the curated source of truth at `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`. Treat schema edits like code: update the curated spec first, then regenerate by building. Keep all instruments behind this single document—extend `InstrumentKind`, geometry, or `PropertySchema` components instead of introducing per‑instrument specs.

Config and identity: FountainStore path is `FOUNTAINSTORE_DIR` (defaults to `.fountain/store`); corpus id is `PATCHBAY_CORPUS` (defaults to `patchbay`). Vendor identity (manufacturerId/family/model/revision) is stored via SecretStore under service `FountainAI.PatchBay`, key `VendorIdentity`.

Key routes (OpenAPI)
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
The app treats this service like AudioTalk’s operator surface: one readiness verdict, a three‑pane layout, and deterministic artifacts (ETags). Suggestions and link edits are typed end‑to‑end so actions are explainable.

Teatro DSL integration
Use the Teatro view/storyboard and MIDI 2.0 DSLs for previews, exports, and CI snapshots. Guidance lives at `External/TeatroPromptFieldGuide/README.md`.
- Export storyboard: map canvas states to Teatro Storyboard scenes and render animated SVG with `External/TeatroFull`.
- Export MIDI: derive a `MIDISequence` from instrument timing/link activity and play via `TeatroPlayerView` alongside the storyboard.
- Import ideas: accept storyboard text via `/import/dsl` to seed graphs (convenience only; not canonical).
- CI: generate a storyboard from a seeded graph and compare frames to baselines (`Scripts/ci/ui-snap.sh`).

### Add an Instrument (spec‑first)

Add new instruments without breaking the contract.
- Update curated spec: edit `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`; extend `components.schemas.InstrumentKind.enum` (e.g., `mvk.scope`, `audiotalk.chat`); add or extend `components.schemas.PropertySchema` (name, type, min/max/step/default; include aliases when renaming).
- Regenerate + build: `swift build --package-path Packages/FountainApps -c debug --target patchbay-service` so `Sources/patchbay-service/openapi.yaml` mirrors the curated doc (do not hand‑edit generated Swift).
- Seed/back data: for defaults, seed in `Packages/FountainApps/Sources/patchbay-service/Handlers.swift` (constructor of `PatchBayCore`); otherwise expose via `/instruments` CRUD (POST → `CreateInstrument`). For UMP ports, set `identity.hasUMPInput/hasUMPOutput`.
- Verify endpoints: `GET /instruments` returns your kind; `GET /instruments/{id}/schema` matches your `PropertySchema`. Quick check: `curl -s http://127.0.0.1:7090/instruments | rg "<your-kind>"`.
- Keep the app in sync: client copy at `Packages/FountainApps/Sources/patchbay-app/openapi.yaml`. Mirror curated edits, then build the app: `swift build --package-path Packages/FountainApps -c debug --target patchbay-app`. Instruments render automatically; add icons/preview actions under `Packages/FountainApps/Sources/patchbay-app/**` as needed.
- Tests: add a seeding test in `Packages/FountainApps/Tests/PatchBayServiceTests` (e.g., assert your kind appears in `listInstruments`). For UI, update snapshot goldens in `Packages/FountainApps/Tests/PatchBayAppUITests/Baselines` and rebaseline with `Scripts/ci/ui-rebaseline.sh` when visuals intentionally change.
- Run locally and in control plane: `swift run --package-path Packages/FountainApps patchbay-service-server`; or `bash Scripts/dev-up --check` to boot the control plane and probe `/health`.
