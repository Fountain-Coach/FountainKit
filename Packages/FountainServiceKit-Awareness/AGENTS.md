# AGENT — Baseline Awareness Service

What: Baseline Awareness provides baseline metrics/events. Spec: `Packages/FountainServiceKit-Awareness/Sources/AwarenessService/openapi.yaml`. Event timelines are delivered via SSE with documented privacy constraints.

Build/test
- Build: `swift build --package-path Packages/FountainServiceKit-Awareness -c debug`
- Tests: `swift test --package-path Packages/FountainServiceKit-Awareness -c debug`

Testing
Unit covers event models and summarizers; integration ensures SSE streams without buffering (chunked NIO). CI builds/tests this package and includes an SSE smoke scenario.
