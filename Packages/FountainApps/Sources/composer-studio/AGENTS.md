# AGENT — Composer Studio (fresh app)

Composer Studio is the composer‑first UI for the product. It replaces the legacy FountainLauncherUI. The source of truth is screenplay text (.fountain) with inline tags; sessions move deterministically through the states “stored (ETag) → parsed model → cue plans → applied notation → journaled (+ UMP)”. The app is OpenAPI‑first, reproducible, and secured via Keychain where needed.

Chat drives the primary interaction: “soften strings after Scene 2”, “apply gentle mood in the intro”. The assistant replies with a short plan and a preview, and offers Apply, Try (temporary), and Undo. Direct manipulation sits alongside chat: an editable screenplay with a tag palette, inline lint/fix, and clickable anchors from chat into text. Previews are immediate and the journal is a readable, explainable timeline — not logs.

The current MVP shows a session strip (ID, ETag, Updated‑at), an actions row (Parse → Map Cues → Apply) gated by preconditions, and results panels for each action (parse warnings, cue count + preview, apply render status + score link). A journal timeline anchors stored/parsed/cued/applied with timestamps. Next, we place chat beside the editor with slash commands (/analyze, /map, /apply, /render, /export), compact diffs/anchors in assistant messages, and a small state bar (Project • Scene • Selection • Tempo/Key).

Operator controls (start/stop/logs) live in scripts; OpenAPI curation remains in the control/curator space. Acceptance for MVP: same input ETag yields the same model/cues/apply, and the journal persists events with proper timestamps/anchors. For MVP+Chat: natural language issues parse/map/apply calls with previews, Apply/Undo are idempotent per ETag, “Try” never mutates the stored score, and warnings carry in‑place “Fix” actions.

Design is SVG‑first in `Design/`. Update `composer-studio-first-open.svg` and `composer-studio-after-analyze.svg` as the source of truth. Edit layout/typography in the SVGs (annotate sizes and font sizes), then implement SwiftUI to match exactly. Acceptance is visual parity within ±4 px and the specified fonts; chat anchors at the bottom; preview behavior follows SVG notes only. Any UI change must be reflected in SVG first; PRs without SVG updates are rejected for layout changes.

Tests cover state gating, parse→map coupling, and journal rendering. Integration runs parse/map/apply against local services.
