# AGENT — Bootstrap Service

Scope: `Packages/FountainServiceKit-Bootstrap/**` — cold‑start and provisioning.
Spec: `Packages/FountainServiceKit-Bootstrap/Sources/BootstrapService/openapi.yaml`.

Principles
- Minimal, idempotent operations; clear error semantics.

Testing & TDD
- Unit: request validation; error mapping.
- Integration: success/failure flow against local stack.

CI gates
- Build + tests; smoke on Studio autostart.

