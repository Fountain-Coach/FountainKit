The Teatro Stage Engine is not itself an HTTP or MIDI service, but hosts may want to expose it via:

- an OpenAPI service (e.g. `/stage/snapshot`, `/stage/playback`),
- a MIDI‑driven instrument that scrubs time or drives camera and rig parameters,
- a file‑based recorder (NDJSON snapshots for later replay).

When integrating with FountainKit:
- Model snapshots using the `snapshot-schema.md` structure.
- If you expose it via Tools Factory or another HTTP surface, keep the payloads close to this schema and mention this repository as the authority.
- Facts and prompts in FountainStore should reference the stage engine by agent id and describe that camera + rig + room are bound together by this model.

