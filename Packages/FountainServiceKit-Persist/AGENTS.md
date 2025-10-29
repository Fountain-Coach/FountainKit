# AGENT — Persist Service

What: Persist exposes the persistence API. Spec: `Packages/FountainServiceKit-Persist/Sources/PersistService/openapi.yaml`. Concurrency hinges on ETags; collections are predictable; capability discovery is explicit.

Build/test
- Build: `swift build --package-path Packages/FountainServiceKit-Persist -c debug`
- Tests: `swift test --package-path Packages/FountainServiceKit-Persist -c debug`

Testing
Unit covers ETag conflict handling and collection operations; integration covers query fixtures and pagination. E2E smoke hits health and minimal CRUD. CI builds/tests this package — no generated sources are committed.
