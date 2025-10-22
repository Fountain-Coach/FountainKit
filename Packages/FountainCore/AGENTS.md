# AGENT — FountainCore (Runtime, Store, Transports)

Scope: `Packages/FountainCore/**` — core primitives (FountainRuntime, FountainStoreClient,
LauncherSignature, NIO transports, crypto helpers). This is the stability anchor all stacks depend on.

Principles
- Back‑compat for public APIs; prefer additive changes. Mark types `Sendable` where feasible.
- No direct coupling to executable targets; provide protocols and adapters only.
- OpenAPI‑first applies to services; here we enforce runtime correctness and safety.

Testing & TDD
- Unit: store capabilities, ETag semantics, HTTP transport behaviors, DNS/crypto helpers.
- Concurrency/actor isolation tests for async APIs.
- Integration smoke: minimal NIO server/client loop.

CI gates
- `swift build` + `swift test` for this package on PRs; zero generated sources committed.

Maintenance
- Document any behavior changes in root AGENTS.md master plan and bump minor versions for additive API.

