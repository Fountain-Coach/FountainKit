# AGENT — FountainAIKit (App-Side Models)

Scope: `Packages/FountainAIKit/**` — app‑side models (e.g., EngraverChatViewModel), persona/awareness helpers.

Principles
- Actor‑isolation correctness; no hard dependency on executable scripts.
- Gateway/environment injected via protocols; Keychain use behind helpers.

Testing & TDD
- Unit: view‑model state transitions, environment controller adapters, persona parsing.
- Integration: gateway/awareness/bootstrap client calls using test doubles.

CI gates
- Build + tests for this package.

