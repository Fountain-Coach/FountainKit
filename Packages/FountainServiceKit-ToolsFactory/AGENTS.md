# AGENT — ToolsFactory Service

Scope: `Packages/FountainServiceKit-ToolsFactory/**` — tools catalog and registration.
Spec: `Packages/FountainServiceKit-ToolsFactory/Sources/ToolsFactoryService/openapi.yaml`.

Principles
- Corpus‑scoped tool lists; idempotent register; stable list format.

Testing & TDD
- Unit: registration normalization; corpus filtering.
- Integration: register AudioTalk spec; list contains expected entries.

CI gates
- Build + tests; Studio autostart registers AudioTalk tools.

