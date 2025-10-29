# PatchBay — Node = Stage (Feature Plan, To Be Discussed)

Status: proposal (to be discussed)
Audience: PatchBay app team, Flow/Canvas maintainers, Teatro/Score teams
Owner: PatchBay Studio

## Why

Unify the mental model: a PatchBay node should behave like a Stage. The Stage is the canvas of meaning; nodes must expose stage‑like structure (baselines/regions) and accept content at those structural attachment points. This removes the need for ad‑hoc overlays and keeps feedback in the node body.

## Scope (initial)

- Node = Stage (rendererless): a node is the container that renders its own content; no separate “renderer” concept.
- Stage family with capacity expressed as input ports mapped to baselines.
- Inline, in‑node feedback (title, compact status) without external overlays.
- Stable, persisted identity (name), live‑updating Flow label, and first‑free numbering on create.

Out‑of‑scope (this round): multi‑page stages, non‑rectangular stages, advanced regions (staff systems, zones), and complex panel layout inside nodes.

## Definitions

- Stage Baseline: horizontal rhythm used to typeset content; spacing defined by `baseline` and trimmed by `margins`.
- Baseline Port: one Flow input per baseline, ordered top→bottom: `in0`, `in1`, …
- Stage Node: `DashKind.stageA4` (later: family `stage.*`).

## Amendment — Rendererless Nodes (Decision)

- Remove the “Renderer” concept from PatchBay. Rendering happens inside a node; a node is the boundary for composition and feedback.
- Consequences:
  - Left pane: drop the Renderers section; the Stage appears under “Dashboard Nodes” (or a “Containers” subsection).
  - Types: deprecate `renderer.stage.*` naming; migrate to `stage.*` (keep runtime aliases for compatibility).
  - Code: StageView remains an internal view used by the Stage node body; there is no separate preview window or overlay pipeline.
  - Docs/tests: update terminology: “Stage node”, not “Stage renderer”.

Migration checklist

1) Types
   - Rename `DashKind.stageA4` → `DashKind.stageA4` (keep enum but treat as container). Identify any lingering “renderer” mentions and remove.
   - Keep a mapping layer to accept legacy `renderer.stage.a4` titles if they appear in old stores.

2) UI
   - Left pane: remove Renderers group; expose “The Stage (A4)” under Dashboard Nodes/Containers.
   - Menus/toolbars: no “Preview/Renderer” verbiage.

3) Runtime
   - Node body owns rendering (title/status + Stage page content). No detached overlays for identity/status.
   - Panel visuals (charts/tables) remain node‑local views when needed, but avoid global overlay layers.

4) Tests
   - Update any snapshot/UITest strings that mention “renderer”.
   - Stage creation + rename + numbering + port count still green.

5) Docs
   - Update AGENTS and plans to remove “renderer” concept; standardize on “Stage node”.


## Functional Requirements

- FR‑1 Capacity mapping
  - Compute baseline count = floor((pageHeight − top − bottom) / baseline).
  - Expose one left input port per baseline (`in0..inN-1`).
  - Recompute ports when `baseline`, `margins`, or `page` changes; preserve existing wires by best‑effort mapping (see Migrate below).

- FR‑2 Inline edit & identity
  - Inline rename on the node handle (double‑click) with Enter/Escape.
  - Persist name in dashboard registry; mirror to PBNode; refresh Flow label live.
  - First‑free numbering on create: derive from live canvas only.

- FR‑3 Node‑body feedback
  - Title always visible (monospace secondary line optional for compact status).
  - No detached overlays for identity/status. Rich page content may still render inside the node body.

- FR‑4 Port HUD (baseline index aid)
  - Small numeric tick near each input dot (0‑based or 1‑based configurable) shown on hover or when stage is selected.
  - Accessibility: provide spoken description, e.g., “Stage ‘Main’, input 12 of 64”.

- FR‑5 Auto‑wire helpers
  - “Connect ← Renderer” targets `in0` by default; allow “Connect to… baseline k” quick pick when k > 0.

## UX Details

- Stage property editor
  - Editable: Title, Page (A4/Letter), Baseline (pt), Margins (top/left/bottom/right).
  - Live preview: recompute port count; show a non‑destructive diff (e.g., “ports 66 → 58”).
  - Apply triggers re‑porting logic: keep edges to still‑valid ports, reassign out‑of‑range to nearest valid index; offer an optional report.

- Port index HUD
  - Toggle from Canvas menu: “Show Baseline Index” (when in selection or always).
  - Styling: 8‑pt label adjacent to the dot, minimal overlap.

## Data Model & API

- Dashboard registry remains the SoT for stage props.
- Ports are derived—do not persist the full port list; recompute from props.
- Migration function when props change: `reflowStagePorts(id: String)`.

## Algorithms

- ComputeBaselines(page, margins, baseline) → Int
- RebuildPorts(stageNode, count) → [PBPort]
- MigrateEdges(oldCount, newCount) → mapping function
  - Keep `in[i]` where i < min(old,new)
  - If i ≥ newCount, remap to `in[newCount-1]` (nearest valid) or prompt when interactive.

## Performance

- Port regeneration should be O(N) where N = baselines (<= ~100). Avoid rebuilding Flow patch unless ids or titles changed; re‑build only for this node when props change.

## Testing

- Unit
  - Baseline math for A4/Letter with multiple margins/baseline values.
  - Recompute ports on props change; assert counts and id order (`in0..`).
  - Edge migration: keep, clamp, and summary mapping.

- Integration
  - Inline rename updates node label and persists after relaunch.
  - Create stage at zoom Z → size scales as expected; port count stable.
  - Port HUD shows correct indices; toggles off/on.

- Snapshot (optional)
  - Node handle with HUD visible at standard zooms.

## Milestones

1) Port count = baselines (A4/Letter, static) — ship
2) Live recompute + migration on props edit — ship
3) Port index HUD + accessibility — ship
4) Auto‑wire “Connect to baseline k” picker — discuss
5) Multi‑page stages (Page n) — discuss (later)

## Open Questions

- Should baseline indexing be 0‑based (internal) or 1‑based (UI)?
- Remapping policy on shrink: clamp to last baseline vs prompt user?
- Do we need named baselines (e.g., staff groups) instead of raw indices?
- How do we visualize extremely dense baseline sets without clutter? (HUD threshold)

## Risks & Mitigations

- High port counts clutter the node edge — mitigate with HUD threshold and hover‑only labels.
- Live recompute could snap wires unintuitively — mitigate with a migration summary and undo support.

## Non‑Goals (now)

- Rendering full score/panel visuals inside the Flow node beyond compact text.
- Custom shapes or rotated stages.

## Rollout & Telemetry

- Feature flag: `PB_STAGE_PORTS_FROM_BASELINES=1` (default ON after bake‑in).
- Log port recompute and migration events with counts for tuning.

## Acceptance (initial)

- Create Stage → ports match baseline count; wiring works to `in0`.
- Change baseline/margins → port count updates; existing wires kept or clamped.
- Inline rename updates label, left list, and persists.
- No detached overlays for titles/status.
