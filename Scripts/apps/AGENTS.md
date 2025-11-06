# AGENT — Scripts/apps (app launchers & packaging)

Scope: `Scripts/apps/**`.

Purpose
- Keep app launchers and packaging scripts together (Studio, Engraver, MemChat, etc.).
- Provide stable shims from legacy paths under `Scripts/`.

Included scripts (canonical)
- `launch-composer-studio.sh` — Launch the new Composer Studio app.
- `launch-audiotalk-studio.sh` — Legacy Studio (deprecated; use `--force-legacy`).
- `launch-engraver-studio-app.sh` — Launch Engraver Studio app.
- `launch-memchat-app.sh` — Launch MemChat app.
- `memchat-oneclick.sh` — One‑click MemChat starter for dev.
- `baseline-patchbay-web` — Seeds Teatro prompts and launches the web mirror (Vite) of Baseline‑PatchBay.
- `midi-service` — Launch the MIDI 2.0 HTTP bridge (`/ump/send`) for web MRTS.
- `quietframe-runtime` — Launch QuietFrame Sonify wired to the MVK runtime (Loopback transport). Sets `QF_USE_RUNTIME=1` and `MVK_BRIDGE_TARGET` (default `QuietFrame#qf-1`).

Conventions
- Keep the UX/config minimal; all environment and secrets managed via Keychain or defaults.
- If a launcher must be deprecated, print a clear message and exit unless forced.
