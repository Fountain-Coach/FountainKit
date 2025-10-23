# AGENT — Scripts/audiotalk (AudioTalk stack)

Scope: `Scripts/audiotalk/**`.

Purpose
- One‑click/dev flows for AudioTalk server stack and tools registration.

Included tools
- `dev-up.sh` — Start AudioTalk + FunctionCaller + ToolsFactory; registers tools (configurable).
- `dev-down.sh` — Stop AudioTalk stack only.
- `oneclick.sh` — Build + run single AudioTalk server, run smoke, optional open browser.
- `run.sh` — Stream logs from audiotalk-server.
- `run-cli.sh` — Run `audiotalk-cli` against a base URL.
- `run-ci-smoke.sh` — Run AudioTalk CI smoke.
- `register-tools.sh` — Register AudioTalk OpenAPI functions into ToolsFactory.

Compatibility
- Legacy paths remain in `Scripts/` and will delegate here until external references are updated.

