# AGENT — Semantic Browser Service

What: Semantic Browser exposes a browser API for indexing and seed. Spec: `Packages/FountainServiceKit-SemanticBrowser/Sources/SemanticBrowserService/openapi.yaml`. Indexing modes are deterministic (quick/standard/deep), and labels/collections are clear and consistent.

Build/test
- Build: `swift build --package-path Packages/FountainServiceKit-SemanticBrowser -c debug`
- Tests: `swift test --package-path Packages/FountainServiceKit-SemanticBrowser -c debug`

Testing
Unit covers URL normalization and label handling; integration exercises seed flows and page/segment/entity endpoints. CI builds/tests this package; optional smoke checks the seed list.
