Teatro Codex macOS Prompt Field Guide — External

What
- Pointer to the external guide: https://github.com/Fountain-Coach/teatro-codex-macos-prompt-field-guide
- This folder serves as the local anchor for documentation and workflows that rely on the Teatro prompt/DSL patterns when working on FountainKit.

Why
- PatchBay (service + app) benefits from Teatro’s Storyboard and MIDI 2.0 DSLs for deterministic demos, previews, and CI‑friendly snapshots.
- The guide documents prompt conventions that help agents author and review DSL snippets safely.

How
- Open the upstream repo for the latest content. Keep references in `Packages/FountainApps/Sources/patchbay-service/AGENTS.md` and `Packages/FountainApps/Sources/patchbay-app/AGENTS.md` in sync with this pointer.
- If we decide to vendor specific excerpts, place them under this directory with explicit source links and commit history notes.

Where (related code/docs)
- PatchBay service guide: Packages/FountainApps/Sources/patchbay-service/AGENTS.md
- PatchBay app guide: Packages/FountainApps/Sources/patchbay-app/AGENTS.md
- Teatro engine (submodule): External/TeatroFull

Maintenance
- Prefer linking to upstream. Do not commit large PDFs or duplicated chapters here.

