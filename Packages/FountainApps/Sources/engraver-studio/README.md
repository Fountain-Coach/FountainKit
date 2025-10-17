Engraver Studio — Environment

Environment variables recognized by Engraver Studio and its core view model:

- FOUNTAIN_GATEWAY_URL: Base URL of the LLM Gateway (default http://127.0.0.1:8010)
- GATEWAY_BEARER / GATEWAY_JWT / FOUNTAIN_GATEWAY_BEARER: Bearer token for gateway auth
- ENGRAVER_CORPUS_ID: Corpus identifier used for persistence and awareness (default engraver-space)
- ENGRAVER_COLLECTION: Store collection for chat turns (default chat-turns)
- ENGRAVER_SYSTEM_PROMPT: Single system prompt injected on each turn
- ENGRAVER_MODELS: Comma-separated model list for the picker (e.g. gpt-4o-mini,gpt-4o)
- ENGRAVER_DEFAULT_MODEL: Default selected model (falls back to first available)
- ENGRAVER_DISABLE_PERSISTENCE: Set to true to disable FountainStore persistence
- ENGRAVER_DEBUG: Set to 1/true to enable verbose diagnostics
- ENGRAVER_DISABLE_AWARENESS: Disable Awareness client wiring
- ENGRAVER_DISABLE_BOOTSTRAP: Disable Bootstrap client wiring
- ENGRAVER_SEED_*: Semantic Browser seeding configuration (see EngraverStudioConfiguration)
- FOUNTAINKIT_ROOT: Absolute path to the repo (enables Environment Manager integration)

Secrets are resolved via SecretStoreHelper:

- FountainAI/GATEWAY_BEARER is used when env vars are absent
- FountainAI/OPENAI_API_KEY is propagated when present

For local development, use the Launcher UI or Scripts/dev-*.sh to bring up the control plane.

