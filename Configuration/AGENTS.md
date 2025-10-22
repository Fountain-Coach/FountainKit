# AGENT — Configuration (persona, defaults)

Scope: `Configuration/**` — persona.yaml, env defaults, auxiliary configs.

Principles
- Persona is versioned file `Configuration/persona.yaml`; Studio edits it in‑place.
- Secrets come from Keychain; do not commit `.env`.

Testing
- Persona YAML ↔ model round‑trip tests in Studio package.

Maintenance
- Document any new config here; keep in sync with Studio editor expectations.

