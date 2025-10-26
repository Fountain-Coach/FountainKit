# AGENT — Bootstrap Service

Bootstrap handles cold‑start and provisioning. Spec: `Packages/FountainServiceKit-Bootstrap/Sources/BootstrapService/openapi.yaml`. Keep operations minimal and idempotent with clear error semantics.

Unit tests cover request validation and error mapping; integration exercises success/failure flows against the local stack. CI builds and tests this package; Studio autostart smokes it during dev.
