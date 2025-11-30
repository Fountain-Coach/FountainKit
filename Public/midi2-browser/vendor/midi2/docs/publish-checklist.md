# midi2.js Publish Checklist

Use this checklist before tagging and publishing a release.

## Prereqs
- [ ] `node_modules/` not committed; repo clean.
- [ ] CI green for midi2.js workflow (tsc, vitest, coverage, build).
- [ ] `dist/` builds cleanly via `npm run build`; `prepare` script set.
- [ ] Version bumped in `package.json`; `private` flag removed when ready to publish.
- [ ] README/AGENTS/gap-plan/DoD updated to reflect current surface area and known gaps.

## Protocol coverage
- [ ] Stream: endpoint/config/function-blocks implemented and validated; group/terminal/process inquiry opcodes addressed or documented.
- [ ] Per-note: management + reg/assignable controllers implemented; pitch bend implemented; any remaining per-note expressives either implemented or documented as out of scope.
- [ ] Down-conversion: MIDI 2.0 → 1.0 paths cover channel voice + SysEx7/8 + MIDI-CI; validation/reserved bits checked.
- [ ] JR: synchronizer wired; scheduler/worker coverage documented.

## Tooling
- [ ] `npm run check`, `npm test`, `npm run coverage` pass locally.
- [ ] Optional: coverage thresholds enforced; lint/static analysis (if added) passes.
- [ ] Bundling strategy decided (tsc emit vs. bundler); `files` field includes outputs only.

## Release steps
1. `npm run clean && npm ci && npm run build && npm test && npm run coverage`.
2. Remove `"private": true` and set version (e.g., `0.1.0`).
3. Commit/tag: `git tag v0.1.0`.
4. Publish: `npm publish` (from midi2.js) or via CI release job.
5. Announce/update changelog.
