# AGENT — Persist Service

Persist exposes the persistence API. Spec: `Packages/FountainServiceKit-Persist/Sources/PersistService/openapi.yaml`. Concurrency hinges on ETags, collections are predictable, and capability discovery stays explicit.

Unit tests cover ETag conflict handling and collection operations; integration covers query fixtures and pagination. E2E smoke hits health and minimal CRUD. CI builds and tests this package — no generated sources are committed.
