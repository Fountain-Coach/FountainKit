# AGENT — Semantic Browser Service

Semantic Browser exposes a browser API for indexing and seed. Spec: `Packages/FountainServiceKit-SemanticBrowser/Sources/SemanticBrowserService/openapi.yaml`. Indexing modes are deterministic (quick/standard/deep), and labels/collections are clear and consistent.

Unit tests cover URL normalization and label handling; integration exercises seed flows and page/segment/entity endpoints. CI builds and tests this package; an optional smoke checks the seed list.
