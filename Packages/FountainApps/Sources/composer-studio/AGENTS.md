# AGENT — Composer Studio (fresh app)

Scope: `Packages/FountainApps/Sources/composer-studio/` — new composer‑first UI.
Status: ACTIVE. This replaces the deprecated `FountainLauncherUI` for product work.

Story (authoritative)
- Screenplay text (.fountain) with inline tags is the source of truth.
- States: Source stored (ETag) → Parsed model → Cue plans → Applied notation → Journaled (+ UMP).
- Deterministic, reproducible, secure (Keychain), OpenAPI‑first.

Interaction Model — Chat‑first (primary)
- Chat drives actions in plain language. Examples: “soften strings after Scene 2”, “apply gentle mood in the intro”.
- Assistant replies with a short plan + preview and offers buttons: Apply, Try (temporary), Undo.
- Direct manipulation alongside chat: editable screenplay with tag palette and inline lint/fix; clickable anchors from chat into text.
- Immediate feedback: cue preview in plain language; apply result shown with a link to score preview.
- Journal is a readable timeline (analyzed, mapped, applied), not logs. Inline warnings appear in the screenplay with quick‑fixes.

MVP (Change Now)
- Session strip at top (ID, ETag, Updated‑at). Create/select.
- Actions row (Parse → Map Cues → Apply) gated by preconditions.
- Results panels:
  - Parse: model summary + warnings.
  - Map: cue count + preview.
  - Apply: render status + score preview link.
- Journal timeline at bottom (stored/parsed/cued/applied with anchors).

MVP+Chat (next sprint)
- Chat pane + editor side‑by‑side. Slash commands for power users: /analyze, /map, /apply, /render, /export.
- Assistant messages contain compact diffs and anchors; “Apply” performs the corresponding API call; “Try” uses a temporary layer; “Undo” reverts last apply.
- State bar (always on): Project • Scene • Selection • Tempo/Key (if available).

Non‑goals (here)
- Operator controls (start/stop/logs) — keep in scripts.
- OpenAPI curation — remains in Control/curator space.

Acceptance (MVP)
- Same input (ETag) → same outputs (model/cues/apply) with cache hits visible.
- Journal events persisted and visible in order with timestamps/anchors.

Acceptance (MVP+Chat)
- Natural language chat issues parse/map/apply calls; messages show previews before apply.
- Apply/Undo are idempotent per ETag; “Try” never mutates the stored score.
- Inline warnings include “Fix” actions that edit tags/text and re‑analyze.

Testing
- Unit: state gating, parse→map coupling, journal rendering.
- Integration: parse/map/apply round‑trip using local services.

Design via SVG (source of truth)
- Location: `Design/`.
  - `Design/composer-studio-first-open.svg` — first‑open layout.
  - `Design/composer-studio-after-analyze.svg` — layout with preview card visible.
- Process (no drift):
  1) Edit the SVG(s) to change layout/spacing/typography. Annotate exact sizes (px) and font sizes (pt). Keep the filenames.
  2) Implement UI to match SVGs exactly (SwiftUI). No unrequested controls, no extra chrome.
  3) Acceptance: visual parity within ±4 px spacing and the specified font sizes; chat anchored at bottom; editor mono font as annotated; preview behavior (slide/fade) only if shown in SVG notes.
  4) Any UI change must be reflected in SVG first; PRs without SVG updates are rejected for layout changes.

Review checklist (UI)
- Editor width and typography match the SVG annotations.
- Chat area height and position match; input anchored; bubbles animate subtly.
- Preview card appears only when content exists; position and action buttons match.
- Journal present where indicated; empty state text matches.
