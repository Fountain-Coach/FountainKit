## PatchBay Service — Agent Guide (OpenAPI‑first)

PatchBay is a CI/PE‑first instrument sketch service. Think QC’s canvas on the wire: nodes are MIDI 2.0 instruments (with PE schemas), and links are explicit mappings (property↔property and UMP→property). The service is a first‑class part of the Fountain stack: it persists graphs in FountainStore, manages vendor identity via SecretStore, and emits corpus snapshots for downstream tools.

Build and run the server with SwiftPM. In the control plane, `Scripts/dev-up` starts PatchBay as a core service; for manual runs, the server binds to `PATCHBAY_PORT` (7090 by default) and falls back to an ephemeral port if busy (printing the bound port).

- Generate + build: `swift build --package-path Packages/FountainApps -c debug --target patchbay-service`
- Run service: `swift run --package-path Packages/FountainApps patchbay-service-server`
- Health: `GET /health` (used by dev-up readiness checks)

Specification lives in `Sources/patchbay-service/openapi.yaml` and mirrors the curated source of truth at `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`. Treat schema changes like code: update the curated spec first, then regenerate and build. Keep all instruments behind this single PatchBay document—extend `InstrumentKind`, geometry, or `PropertySchema` components as needed instead of creating per-instrument specs so the server and PatchBay app stay in lock-step.

When adding an instrument, describe its knobs through `PropertySchema`, add or reuse enum cases under `InstrumentKind`, and regenerate with `swift build` so `/instruments` and `/instruments/{id}/schema` surface the payload exactly as the client expects. If an instrument needs external services, integrate them behind PatchBay’s existing routes rather than branching new OpenAPI contracts.

Storage and identity are simple by default. FountainStore is addressed via `FOUNTAINSTORE_DIR` (defaults to `.fountain/store`); the corpus id is `PATCHBAY_CORPUS` (defaults to `patchbay`). Vendor identity (manufacturerId/family/model/revision) is stored with SecretStore under service `FountainAI.PatchBay`, key `VendorIdentity`.

Core routes (OpenAPI)
- Canvas: `/canvas`, `/canvas/zoom(… )`, `/canvas/pan`
- Instruments: `/instruments` (CRUD), `/instruments/{id}/schema`
- Links: `/links` (CRUD, property↔property and UMP→property)
- Discovery: `/ci/endpoints`, `/ci/endpoints/{id}/schema`
- Suggestions: `/graph/suggest` (CI/PE‑grounded auto‑noodling)
- Import/Export: `/graph`, `/export/json|dsl`, `/import/json|dsl`
- Store: `/store/graphs`, `/store/graphs/{id}` (persist `GraphDoc` as `patchbay.graphs`)
- Corpus: `/corpus/snapshot` (AI‑readable snapshot)
- Admin: `/admin/vendor-identity` (GET/PUT), `/admin/vendor-identity/allocations` (GET/POST)

Operator UX parity
The PatchBay app treats this service like AudioTalk’s operator surface: readiness with a single verdict, a three‑pane layout, and deterministic artifacts (ETags) for reproducible sessions. Suggestions and link CRUD stay typed end‑to‑end so actions are explainable.

### Instrument Addition Checklist (spec‑first)

Add a new instrument without breaking the app/service contract.

1) Update curated spec (source of truth)
   - Edit `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`.
   - Extend `components.schemas.InstrumentKind.enum` with your instrument kind (e.g., `mvk.scope`, `audiotalk.chat`).
   - Add or extend `components.schemas.PropertySchema` entries to describe all knobs (name, type, min/max/step/default, aliases when renaming).

2) Regenerate and build
   - Run `swift build --package-path Packages/FountainApps -c debug --target patchbay-service` to let `Sources/patchbay-service/openapi.yaml` mirror the curated doc (do not hand‑edit generated Swift).

3) Seed or back instrument data
   - If the instrument should appear by default, seed it in `Sources/patchbay-service/Handlers.swift` (constructor of `PatchBayCore`).
   - Otherwise, expose it via `/instruments` CRUD (POST → `CreateInstrument`).
   - For UMP ports, set `identity.hasUMPInput/hasUMPOutput` accordingly.

4) Verify endpoints
   - `GET /instruments` returns your kind; `GET /instruments/{id}/schema` matches the `PropertySchema` you defined.
   - Quick check: `curl -s http://127.0.0.1:7090/instruments | rg "<your-kind>"`.

5) Keep the app in sync
   - The app’s client copy lives at `Sources/patchbay-app/openapi.yaml`. If schemas changed, mirror the curated edits there, then `swift build --package-path Packages/FountainApps -c debug --target patchbay-app` to regenerate.
   - In the app, instruments render automatically; add icons or preview actions as needed under `Sources/patchbay-app/**`.

6) Tests
   - Add a seeding test in `Tests/PatchBayServiceTests` (e.g., assert your kind is present in `listInstruments`).
   - If UI changes, add/update snapshot goldens in `Tests/PatchBayAppUITests/Baselines` and run `Scripts/ci/ui-rebaseline.sh` when visuals intentionally change.

7) Run locally and in control plane
   - Manual run: `swift run --package-path Packages/FountainApps patchbay-service-server`.
   - Dev‑up: `bash Scripts/dev-up --check` boots the full control plane and probes `/health`.
