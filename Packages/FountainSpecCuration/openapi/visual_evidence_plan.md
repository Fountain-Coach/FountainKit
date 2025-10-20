# Visual Evidence Map — Concept and Implementation Plan

Date: 2025-10-23
Owner: MemChat / Semantic Browser / Persist

## Objective
Make MemChat’s memory coverage visual, verifiable, and explorable. Show precisely what the system “knows” about a source (web page or file) by overlaying stored evidence on a faithful visual of the source, and enable quick diffing of covered vs missing vs stale regions, with drill‑down to the underlying segments/baselines/citations.

## Core Ideas
- Truth image: pixel‑accurate snapshot of the source (full‑page browser screenshot; rendered PDF page images; HTML/Markdown/WebView render for files).
- Anchors: for every stored segment we record one or more bounding boxes (screen coordinates in the truth image space) plus a normalized text excerpt for fallback matching.
- Overlay layers:
  - Covered (green): regions mapped to stored segments.
  - Stale (amber): covered but older than a threshold vs source fetch time.
  - Missing (red hatch): source text regions with no stored mapping above confidence.
  - Notes (blue): pins anchored to baselines/drift/patterns/reflections.
- Interactions: hover previews (snippet + corpus/segment ID), click to open segment; toggle layers and recency filter; coverage % bar; actions to re‑index a region or add a note.

## OpenAPI‑First Plan

### Phase 1 — Specs + Data
- Update `v1/semantic-browser.yml` (Snapshot/Analysis):
  - Snapshot: add `image` (PNG, full‑page), `width`, `height`, `scale`, `viewport`, `scrollHeight`.
  - `Analysis.blocks[]`: add `rects[]` (x,y,w,h in screenshot coords) and `excerpt`.
  - Index result: include persisted anchor info and simple coverage metrics per page.
- Store schema (document‑friendly; no table migrations required):
  - Segment.visualAnchors: `[{ imageId, rect:{x,y,w,h}, sourceId, excerpt, confidence, ts }]`
  - VisualAsset: `{ imageId, kind, width, height, scale, source:{ url|filePath, contentType, fetchedAt } }`
- Regenerate types/clients/servers via `swift-openapi-generator` for any targets touching the spec.

### Phase 2 — Capture + Anchoring
- Web (Semantic Browser):
  - Use CDP to capture full‑page PNG and DOM clientRects for analysis blocks.
  - Normalize rects to image coordinate space; record `scale`.
  - Store the PNG in an asset store (disk/S3); return `imageId` in API.
- Files:
  - PDF: render each page to image; detect paragraph bounds (PDFKit text selections) and emit rects.
  - HTML/Markdown: load in WKWebView/headless WebView; extract clientRects for paragraphs; render full content image.
  - TXT/RTF: lay out via TextKit; compute bounding rects; render to image.

### Phase 3 — Index + Diff
- During `/v1/index`, persist segment `visualAnchors` and `visualAsset` metadata.
- Build a “coverage map” per asset:
  - Covered = union of segment rects.
  - Missing = source paragraph rects minus covered.
  - Stale = covered where `segment.ts < snapshot.ts − threshold`.
- Fallback matching: fuzzy match segment `excerpt` against snapshot text to repair anchors and mark approximate confidence.

### Phase 4 — Viewer (MemChat Apps)
- EvidenceMapView (SwiftUI): renders the truth image with overlay layers; zoom/pan; hover tooltips; coverage %; layer toggles.
- Entry points:
  - Chat right pane → “Visual Evidence”.
  - Hosts sheet row → “Open Map”.
  - Evidence sheet → “Open Map”.
- Drill‑down: click region → open segment details (copy, open in store), “re‑index region,” “add note.”

### Phase 5 — Actions + Edit
- Re‑index region: for web, re‑browse with selector bounding the region; for files, re‑segment selected rects and re‑write segments.
- Add note/pin: persist a reflection/note anchored at a rect; show as blue pin overlay.

### Phase 6 — Perf + Caching
- Cache downsampled image tiles; lazy‑load overlays per zoom.
- Precompute merged coverage masks for fast redraw.
- Progressive loading: show image first, stream overlays via SSE/chunked JSON.

### Phase 7 — CI + QA
- Unit tests for rect normalization and set operations (union/subtraction), excerpt matching, and confidence thresholds.
- Golden images for sample pages/files; assert overlay counts and coverage metric.

## Data Model (concise)
- VisualAsset: `{ imageId, kind:"web|pdf|html|md|text", width, height, scale, source:{url|filePath, contentType, fetchedAt} }`
- VisualAnchor: `{ imageId, rect:{x,y,w,h}, segmentId, excerpt, confidence, ts }`

## UX Notes
- Evidence Depth continues to govern the textual FactPack used for deep answers; the visual map shows the entire source surface to make gaps obvious.
- Add a recency slider (e.g., 30/60/90 days) to label stale regions.

## Integrations
- SemanticBrowserSeeder: optional `includeVisuals=1` to fetch `imageId` + anchors during indexing.
- MemChatController: loaders to fetch `VisualAsset` + overlays by host/pageId/file URL.
- Persist service: asset fetch endpoints when remote storage is used; for local dev, load from disk paths.

## Phasing to Land
1) Spec + generator types for visuals.
2) Browser capture + rect anchoring + persisted anchors.
3) Minimal viewer (image + covered layer + coverage %).
4) Missing/stale layers + “open segment” drill‑down.
5) File pipelines (PDF/HTML/MD/RTF/TXT).
6) Actions: re‑index region; add note; polish.

