# AGENT — FountainAIKit (app‑side models)

`Packages/FountainAIKit/**` hosts app‑side models (for example, EngraverChatViewModel) and persona/awareness helpers. Keep actor isolation correct and avoid hard dependencies on executables; inject gateway/environment via protocols and defer any secret handling to Keychain helpers.

Unit tests cover view‑model state transitions, environment controller adapters, and persona parsing. Integration exercises gateway/awareness/bootstrap client calls using test doubles. CI builds and tests this package in isolation.
