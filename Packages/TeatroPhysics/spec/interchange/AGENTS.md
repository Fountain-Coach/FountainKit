This directory defines how the Teatro Stage Engine exposes its state to other systems: snapshots, logs, and potential network APIs. The goal is that a host like FountainKit can record and replay a session, or drive a renderer in another language, without guessing field names.

Files:
- `snapshot-schema.md` — the logical structure of a frame.
- `integration-notes.md` — how this maps into OpenAPI/PE or other host‑level abstractions.

For the end‑to‑end picture of how these interchange rules become FountainKit instruments and tools (Stage World, Puppet, Camera, Recording), see `Design/TeatroStage-Instruments-Map.md` at the FountainKit root.
