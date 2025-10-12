# Persistence Seeding – `the-four-stars`

ArcSpec evolution requires rich corpus context inside FountainStore. This guide
describes how to seed the `the-four-stars` repository into the persistence layer
so studios can derive meaningful arcs.

## Source Repository

- GitHub: <https://github.com/Fountain-Coach/the-four-stars>
- Contents: multilingual texts, commentaries, MIDI stems, annotations.

## Target Layout

| Collection | Description | Source path |
| --- | --- | --- |
| `corpus_documents` | Canonical text passages with metadata (language, stanza, meter). | `texts/*.md` |
| `translations` | Translation pairs linked to source passage IDs. | `translations/*.md` |
| `annotations` | Commentary, argument threads, motif tags. | `annotations/*.json` |
| `audio_refs` | MIDI / audio references with cue points. | `audio/**/*.mid` |

Each record should be tagged with `corpusId = "the-four-stars"` and stored under
`/data/corpora/the-four-stars/…` in FountainStore.

## Seeding Script (draft)

Create a Swift script / CLI (`swift run seeder --repo <path> --corpus the-four-stars`)
that performs:

1. Clone/update the repo to a local cache (read-only).
2. Walk expected directories, parsing content:
   - Markdown → structured text passages (use front-matter for IDs).
   - JSON annotations → typed models.
   - Audio/MIDI → copy to artifact store and record metadata.
3. Write batches into FountainStore via the existing persistence service client
   (`PersistAPI`).
4. Emit an ingestion manifest (`seed-manifest.json`) with checksums for replay.

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

- [ ] Implement seeding CLI (Swift executable or script).
- [ ] Define mapping from Markdown metadata → `PersistAPI` request models.
- [ ] Agree on artifact storage quotas for MIDI/Audio assets.
- [ ] Automate periodic re-seeding (cron or GitHub Actions trigger).
