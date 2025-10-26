# AGENT — FountainProviders (LLM providers)

`Packages/FountainProviders/**` hosts OpenAI, gateway, and local providers behind a shared protocol. Document the env‑var policy and prefer Keychain helpers for secrets so tests can run safely.

Unit tests cover request building and error mapping. Integration probes are opt‑in and skipped without keys. CI builds and tests the package and never performs live calls unless keys are explicitly provided.
