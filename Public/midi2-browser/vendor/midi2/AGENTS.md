# midi2.js / AGENTS

## Mission and current coverage
- Cross-browser TypeScript core for MIDI 2.0 UMP + MIDI-CI with no CoreMIDI/DOM dependencies in the core exports.
- Implemented: UMP encode/decode for utility, system, MIDI 1.0 channel voice, and MIDI 2.0 channel voice (incl. per-note management/registered/assignable controllers and per-note pitch bend); Flex Data for tempo/time signature/key signature/lyric; SysEx7/8 fragmentation + reassembly; MIDI-CI envelopes (discovery, endpoint inquiry, profiles, property chunking, process inquiry); scheduler with jitter tolerance + record/replay; streaming decoder that reassembles SysEx and surfaces MIDI-CI; demo adapters for WebAudio, Three.js, Cannon.js.
- Tests: `npm test` (vitest) currently covers UMP, SysEx, MIDI-CI helpers, scheduler, and the stream decoder. `npm run check` runs TypeScript. CI mirrors this in `.github/workflows/midi2-js.yml`.
- Build: `npm run build` (tsup) emits ESM+CJS+types to `dist/`; package is versioned (0.1.0) and no longer marked private.
- Canonical sources: protocol facts must originate from `midi2.full.closed.schema.json` / `midi2.full.openapi.json`. When extracting details from PDF specs, render the relevant pages to images (e.g., `gs -sDEVICE=png16m -o /tmp/page.png -dFirstPage=N -dLastPage=N M2-104-UM_v1-1-2_UMP_and_MIDI_2-0_Protocol_Specification.pdf`), interpret the bit layout, and update/annotate the JSON schema/OpenAPI accordingly before changing code. Document the source section/page for any derived behaviors.

## Gaps vs DoD (sync with `docs/midi2-js-dod.md` and `midi2.js/docs/gap-plan.md`)
- Protocol: stream config/function block UMP covered (incl. process inquiry opcode 0x03); group/terminal semantics are informational only in spec. Per-note management/reg/assignable controllers and per-note pitch bend are implemented; other per-note expressives remain via controllers. MIDI 1.0 down-conversion/validation (SysEx7/8 + MIDI-CI emit) should be tightened with reserved-bit checks. Jitter Reduction synchronizer exists and is wired into the scheduler; worker-clock coverage still pending.
- MIDI-CI: discovery/profile/property/process flows lack compression/state/error handling, MUID management, and ACK/NAK paths; property exchange helpers are limited to chunk framing.
- Validation: reserved-bit and range enforcement is partial; negative tests exist but do not yet cover malformed stream/flex/CI variants beyond current cases.
- Tooling/distribution: tsup emits ESM/CJS+types to `dist/` and package is non-private; still need coverage reporting and CI gating publish artifacts (no vendored `node_modules`).
- Adapters: minimal demos only; per-note controllers, pitch-bend range negotiation, and disposal safety remain to be hardened.
- Docs: README and docs must track coverage as gaps close; keep DoD and the gap plan aligned with implemented features.

## Workflow
- Default commands (run from `midi2.js`): `npm run check`, `npm test`, `npm run build`. Vitest here does not support `--runInBand`.
- Add tests alongside new protocol handlers; prefer `Uint32Array`/`Uint8Array` fixtures that mirror JSON Schema/OpenAPI expectations.
- Update `AGENTS.md`, `docs/midi2-js-dod.md`, and `midi2.js/docs/gap-plan.md` when adding/removing protocol surface area or changing public APIs.
- Keep core logic in `src/*` platform-agnostic; adapters stay isolated under `src/adapters/*`.
