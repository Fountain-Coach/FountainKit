# Persistence Seeding – `the-four-stars`

ArcSpec evolution requires rich corpus context inside FountainStore. This guide
describes how to seed the `the-four-stars` repository into the persistence layer
so studios can derive meaningful arcs.

## Source Repository

- GitHub: <https://github.com/Fountain-Coach/the-four-stars>
- Contents: multilingual texts, commentaries, MIDI stems, annotations.

## Current Corpus Structure

`the-four-stars` currently ships a single transcript (`the four stars.txt`). The
`persistence-seeder` CLI performs two key actions:

1. **Analysis (`--analyze`)** – enumerates extensions/directories and samples
   metadata so we can understand the corpus layout.
2. **Derivation (default mode)** – parses the transcript into individual
   speeches, one per narrator, tagging each with act, scene, location, and
   speaker.

The derived speeches are emitted under logical paths such as:

```
derived/the-four-stars/act-i/scene-1/orlando-1
derived/the-four-stars/act-i/scene-1/adam-2
...
```

Each record carries metadata similar to:

```json
{
  "type": "speech",
  "act": "I",
  "scene": "I",
  "location": "Orchard of Oliver's house.",
  "speaker": "ORLANDO",
  "index": "1"
}
```

The CLI writes a deterministic `seed-manifest.json` with SHA-256 hashes so the
ingest step can be replayed or diffed safely.

## Usage

```bash
# Inspect repository structure
swift run --package-path Tools/PersistenceSeeder \  persistence-seeder --repo /path/to/the-four-stars --analyze

# Generate seed manifest with derived speeches
swift run --package-path Tools/PersistenceSeeder \  persistence-seeder \  --repo /path/to/the-four-stars \  --corpus the-four-stars \  --source https://github.com/Fountain-Coach/the-four-stars \  --out .fountain/seeding/the-four-stars
```

Output: `.fountain/seeding/the-four-stars/seed-manifest.json`

## Idempotency & Replay

- Use deterministic IDs derived from file paths or explicit front-matter IDs.
- Store SHA256 hash per source file to detect changes.
- Support `--dry-run` to preview inserted/updated records.
- Log all import actions to `/logs/seeding/the-four-stars/<timestamp>.log`.

## Integration with ArcSpec Plan

- Seeding must run **before** ArcSpec derivation for the polyglot studios.
- Record the ingestion manifest path in future ArcSpecs (`corpus.refs` array).
- Add the seeding CLI to CI (optional) or run manually before studio releases.

## Next Steps

- [x] Implement seeding CLI (`Tools/PersistenceSeeder`).
- [ ] Define mapping from derived speeches → `PersistAPI` request models.
- [ ] Agree on artifact storage quotas for MIDI/Audio assets.
- [ ] Automate periodic re-seeding (cron or GitHub Actions trigger).
