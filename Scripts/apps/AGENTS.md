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

Conventions
- Keep the UX/config minimal; all environment and secrets managed via Keychain or defaults.
- If a launcher must be deprecated, print a clear message and exit unless forced.

