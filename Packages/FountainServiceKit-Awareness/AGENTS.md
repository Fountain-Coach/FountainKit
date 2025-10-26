# AGENT — Baseline Awareness Service

Baseline Awareness provides baseline metrics/events. Spec: `Packages/FountainServiceKit-Awareness/Sources/AwarenessService/openapi.yaml`. Event timelines are delivered via SSE with documented privacy constraints.

Unit tests cover event models and summarizers; integration ensures SSE streams without buffering (chunked NIO). CI builds and tests this package and includes an SSE smoke scenario.
