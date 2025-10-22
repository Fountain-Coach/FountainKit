# AGENT — FountainProviders (LLM Providers)

Scope: `Packages/FountainProviders/**` — OpenAI/gateway/local providers.

Principles
- Env var policy documented; Keychain helper usage recommended for secrets.
- Pluggable providers implement a common protocol.

Testing & TDD
- Unit: provider request building; error mapping.
- Integration: live probes are opt‑in/skipped without keys.

CI gates
- Build + tests; no live calls without explicit keys in CI.

