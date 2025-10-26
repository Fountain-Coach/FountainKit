# AGENT — FountainCore (runtime, store, transports)

`Packages/FountainCore/**` is the stability anchor for everything else: FountainRuntime, FountainStoreClient, LauncherSignature, NIO transports, and small crypto helpers live here. Keep public APIs backward‑compatible and prefer additive changes; where feasible, mark types `Sendable`. Executables shouldn’t bleed into this package — offer protocols and adapters instead.

Testing focuses on behavior, not wiring: store capabilities and ETag semantics, HTTP transport behavior, and DNS/crypto helpers. For async APIs, include concurrency and actor‑isolation tests. A minimal NIO server/client loop serves as the integration smoke.

CI must pass `swift build` and `swift test` for this package, and no generated sources are committed. When you change behavior, document it in the root AGENTS.md master plan and bump a minor version for additive API.
