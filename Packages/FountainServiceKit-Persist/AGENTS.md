# AGENT — Persist Service

Scope: `Packages/FountainServiceKit-Persist/**` — persistence API.
Spec: `Packages/FountainServiceKit-Persist/Sources/PersistService/openapi.yaml`.

Principles
- ETag concurrency, predictable collections, capability discovery.

Testing & TDD
- Unit: ETag conflict handling and collection ops.
- Integration: query fixtures & pagination.
- E2E: Studio smoke uses persist health + minimal CRUD.

CI gates
- Build + tests; no generated sources.

