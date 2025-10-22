# AGENT — Baseline Awareness Service

Scope: `Packages/FountainServiceKit-Awareness/**` — baseline metrics/events.
Spec: `Packages/FountainServiceKit-Awareness/Sources/AwarenessService/openapi.yaml`.

Principles
- Event timelines; SSE; privacy constraints documented.

Testing & TDD
- Unit: event models and summarizers.
- Integration: SSE streaming without buffering (chunked NIO path).

CI gates
- Build + tests; SSE smoke scenario.

