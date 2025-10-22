# Composer Studio — Full User Story and SVG‑Driven Plan

This document is the single source for the end‑to‑end user story and the
SVG‑driven workflow used to specify the Composer Studio GUI. The SVGs in this
folder are the authoritative wireframes; SwiftUI must match them exactly.

## User Story (End‑to‑End)
- Start/Return: Opens to the last piece or “New screenplay”. No setup.
- Write: Types screenplay; adds inline tags. Autosave; never loses work.
- Say (Chat): Describes musical intent in plain words. Assistant replies with a short preview.
- Analyze: System parses scenes/notes and maps cues. Shows concise summary and warnings.
- Decide: One tap — Apply or Not yet. Undo always available. “Try” = safe audition.
- Hear/See: Score updates; preview or link opens the engraved result. (Optional) UMP for devices.
- Remember: Journal records stored/parsed/cued/applied with timestamps/anchors; deterministic via ETags.
- Continue: Close and return later — resumes exactly where left off.
- Export/Share: Cue sheet (CSV/PDF) and rendered score (SVG/PDF). No secrets exposed.

## States
- No Project → Project Active (autosaved draft)
- Source Stored (ETag) → Parsed (model+warnings) → Cued (plans) → Applied (score updated) → Journaled (timeline)
- Optional: Preview/Try layer (non‑mutating)

## Primary Flows
- Write → Analyze → Preview → Apply/Undo → Journal updated
- Chat intent → Preview → Apply/Undo → Journal updated
- Import → Analyze → Continue
- Export cue sheet/score → Share

## Artifacts & Data
- Screenplay source (text, ETag, updatedAt)
- Parsed model summary (scenes, beats, tags, warnings)
- Cue list (plain language + anchors)
- Apply result (status + preview link)
- Journal (events with timestamps + anchors)

## Screens (Wireframes to author in SVG)
- First Open: Editor left, “Ready” hint; chat input right; no preview card yet.
- After Analyze: Preview card (Analysis + Cues, Apply chip) slides in above chat.
- After Apply: Apply tab shows “Applied N cues • OK” + link to score/preview.
- Error/Conflict: One‑line plain error with a “Fix” suggestion.
- Journal Timeline: Compact list with time, action, anchor.

## SVG System (Prompt Spec)
- Canvas: 1440×900; base grid 8px; margins 24px outer, 12px inner.
- Typography:
  - Editor mono: Menlo/Consolas 16pt
  - Labels 14pt; Body 13pt; Captions 12pt
- Layout:
  - Left editor: 360–420px fixed min width; journal below.
  - Right column: Preview card (~120–160px) above a 260–300px chat region; chat input anchored.
- Colors (light): background #f4f4f4; cards #ffffff; strokes #e0e0e0; accent #0A84FF; soft text #888
- Element IDs (for implementation hooks): `editor`, `journalList`, `chatList`, `chatInput`, `previewCard`, `applyButton`, `readyBadge`.
- Files:
  - `Design/composer-studio-first-open.svg` (first‑open)
  - `Design/composer-studio-after-analyze.svg` (after‑analyze)

### Acceptance (visual)
- Parity within ±4px of annotated sizes; specified font sizes present.
- Chat anchored; editor mono; preview card behavior as annotated in SVG notes.

## Reusable Prompt Templates (for generating SVGs)

First‑open SVG prompt
```
Create a 1440×900 SVG for “Composer Studio — first open”.
Use: background #f4f4f4, cards #fff, strokes #e0e0e0, accent #0A84FF.
Left column: 360–420px rounded card with id=editor; 16pt monospaced sample text (title + two lines + one tag).
Below left: journal card id=journalList with “(empty)”.
Right: small “Ready” indicator (id=readyBadge). Chat list id=chatList and input bar id=chatInput anchored at bottom (40px height). No preview card.
Labels: “Screenplay”, “Chat”. Use 13–14pt system fonts for labels/body.
Self‑contained SVG with inline <style> only.
```

After‑analyze SVG prompt
```
Same as first‑open, plus a preview card (id=previewCard) above chat (~140px):
  Analysis: “scenes=1 beats=0 notes=1 • 0 warnings”
  Cues: “mood gentle → p, moderato”
  Apply chip/button (id=applyButton) top‑right of card.
```

## Milestones
- M0 Wireframes: finalize SVGs (accepted).
- M1 Layout Implementation: SwiftUI matches SVGs; no logic.
- M2 Analyze/Preview: parse+map; show summaries; slide preview card.
- M3 Apply/Undo: apply endpoint; status/link; Undo.
- M4 Journal: live events; readable entries.
- M5 Export: cue sheet CSV/PDF; score preview.
- M6 Polish: animations, spacing, persistence, accessibility.

## No‑Drift Rules
- Any layout/typography change starts in SVG. PRs changing UI without SVG updates are rejected.
- The app implements exactly what’s in SVGs; no unrequested controls or panels.

