# AGENT — Bootstrap Service

What: Bootstrap handles cold‑start and provisioning. Spec: `Packages/FountainServiceKit-Bootstrap/Sources/BootstrapService/openapi.yaml`. Keep operations minimal and idempotent with clear error semantics.

Build/test
- Build: `swift build --package-path Packages/FountainServiceKit-Bootstrap -c debug`
- Tests: `swift test --package-path Packages/FountainServiceKit-Bootstrap -c debug`

Testing
Unit covers request validation and error mapping; integration exercises success/failure flows against the local stack. CI builds/tests this package; Studio autostart smokes it during dev.
