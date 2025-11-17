# Tools Factory Server — Agent Guide

What
- Hosts the Tools Factory service (curation → tools registry) and provides a runtime endpoint to generate and seed MIDI‑CI facts from OpenAPI.

Why
- Keep OpenAPI as the single source of truth. Enable fast, runtime authoring: submit a spec and immediately get back PE facts that the MIDI 2.0 host exposes as properties.

How
- Start: `Scripts/dev/tools-factory-min run` (default `:8011`).
- Health/spec: `GET /metrics`, `GET /openapi.yaml`.
- Generate facts from OpenAPI: `POST /agent-facts/from-openapi`
  - Request (JSON):
    - `agentId` (required): `fountain.coach/agent/<name>/service`
    - `corpusId` (optional): target corpus (default `agents`)
    - `seed` (optional, default true): write into FountainStore
    - One of:
      - `openapi`: object or YAML/JSON string of the spec
      - `specURL`: URL to fetch the spec (e.g., a service’s `/openapi.yaml`)
  - Response: facts JSON. When `seed=true`, the server also writes to `agent-facts/facts:agent:<safeId>`.

Where
- Server main: `Packages/FountainApps/Sources/tools-factory-server/main.swift:1`.
- Service kit: `Packages/FountainServiceKit-ToolsFactory/Sources/ToolsFactoryService/*`.
- Facts consumer: MIDI host (`Packages/FountainApps/Sources/midi-instrument-host`) polls FountainStore and exposes properties.

Notes
- Keep runtime seeding gated in production via network policy or auth tokens. Specs remain curated under `Packages/FountainSpecCuration/openapi` during development.
