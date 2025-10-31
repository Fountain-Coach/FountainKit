# AGENT — FountainCore (runtime, store, transports)

What: `Packages/FountainCore/**` is the stability anchor: FountainRuntime, FountainStoreClient, LauncherSignature, NIO transports, and small crypto/DNS helpers live here. Keep public APIs backward‑compatible and prefer additive changes; mark types `Sendable` when feasible. Executables must not bleed into this package — offer protocols and adapters instead.

Where code lives
- Runtime/store: `Packages/FountainCore/Sources/FountainRuntime`, `Packages/FountainCore/Sources/FountainStoreClient`
- Transports: `Packages/FountainCore/Sources/FountainRuntime/NIO*`
- Launcher signature/helpers: `Packages/FountainCore/Sources/FountainRuntime/LauncherSignature*`, `Packages/FountainCore/Sources/FountainRuntime/Crypto*`, `DNS/*`

Build/test
- Build: `swift build --package-path Packages/FountainCore -c debug`
- Tests: `swift test --package-path Packages/FountainCore -c debug`

Testing
Focus on behavior: store capabilities and ETag semantics, HTTP transport behavior, DNS/crypto helpers. For async APIs, include concurrency and actor‑isolation tests. A minimal NIO server/client loop serves as integration smoke.

CI
`swift build` and `swift test` must pass for this package; no generated sources are committed. When behavior changes, document it in the root AGENTS master plan and bump a minor version for additive APIs.

Baseline policy (cross‑package)
- The default UI baseline is Baseline‑PatchBay (grid‑dev‑app). Changes that affect viewport math or instrument semantics should coordinate with the baseline’s MRTS Teatro prompt and robot invariants. The baseline prints the creation + MRTS prompts on boot; seed MRTS via `baseline-robot-seed` and run invariants with `Scripts/ci/baseline-robot.sh`.
