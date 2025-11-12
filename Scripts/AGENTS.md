# AGENT — Scripts (lifecycle and tooling)

The `Scripts/**` tree is first‑class product code: lifecycle helpers for the control plane, CI smoke tests, OpenAPI utilities, and app‑adjacent tools. Scripts are idempotent, safe to re‑run, and explain themselves with a short `Usage:`; no checked‑in `.env` — secrets come from Keychain with sensible defaults.

Conventions
- Defensive by default: check ports and stale PIDs before starting servers; always set `LAUNCHER_SIGNATURE` (Keychain‑backed with a default).
- Shell: prefer POSIX sh or bash with `set -euo pipefail`.
- State: logs under `.fountain/logs`, PIDs under `.fountain/pids` at repo root.
- Tests: live under `Scripts/tests/**` to drive readiness/route probes.

Areas (canonical)
- `Scripts/design/` — GUI/engraving tooling (source of truth in `Design/`).
- `Scripts/openapi/` — spec lint and curated‑list validator.
- `Scripts/ci/` — workspace smoke and optional toolserver smoke.
- `Scripts/dev/` — workspace lifecycle (up/down/status/prebuild/keychain).
- `Scripts/audiotalk/` — AudioTalk stack runners and tool registration.
- `Scripts/apps/` — app launchers (composer, legacy studio, engraver, memchat).
- `Scripts/memchat/` — deprecated; runnable but not active product work.
 - `Scripts/apps/baseline-patchbay-web` — seeds prompts and starts the external web mirror (Vite).
 - `Scripts/apps/midi-service` — starts the MIDI 2.0 HTTP bridge for UMP send/record and headless instruments.

## Targeted Wrappers (Service‑Minimal)

What
- Minimal build/run wrappers to compile just one server target with small graphs. They set `FK_SKIP_NOISY_TARGETS=1` and skip launcher signature checks for fast local loops. Servers run as real HTTP only (no smoke in mains).

Why
- Speeds up iteration when full‑workspace builds take minutes. Each wrapper narrows SwiftPM planning/compilation to a single executable target.

How
- Usage: `Scripts/dev/<service>-min [build|run]`. Examples:
  - `Scripts/dev/gateway-min [build|run]`
  - `Scripts/dev/pbvrt-min [build|run]`
  - `Scripts/dev/quietframe-min [build|run]`
  - `Scripts/dev/planner-min [build|run]`
  - `Scripts/dev/function-caller-min [build|run]`
  - `Scripts/dev/persist-min [build|run]`
  - `Scripts/dev/baseline-awareness-min [build|run]`
  - `Scripts/dev/bootstrap-min [build|run]`
  - `Scripts/dev/tools-factory-min [build|run]`
  - `Scripts/dev/tool-server-min [build|run]`
- Environment (set by wrappers): `FK_SKIP_NOISY_TARGETS=1`, `FOUNTAIN_SKIP_LAUNCHER_SIG=1`.

Where
- Wrappers live in `Scripts/dev/*-min`. Server targets live under `Packages/FountainApps/Sources/<service>-server` and depend on cores that own OpenAPI generation.

Codex danger (sentinel‑gated)
- Launcher: `Scripts/dev/codex-danger`.
- Profiles:
  - Safe (default): `--full-auto` (workspace‑write; approvals on‑failure).
  - Danger (opt‑in): `-s danger-full-access -a never`.
- Activate danger: create `.codex-allow-danger` at repo root (git‑ignored), or set `FK_CODEX_DANGER=1`, or pass `--danger`. Force safe with `--safe`.
- GitHub auth: reuses `gh auth token` when available; `--relogin` forces a fresh login.

Baseline policy
- `Scripts/apps/baseline-patchbay` launches the Baseline‑PatchBay UI. This baseline is authoritative for viewport/math invariants; any change to the baseline app must be paired with a matching MRTS Teatro prompt printed on boot and persisted via `baseline-robot-seed`. Run the invariants subset with `Scripts/ci/baseline-robot.sh`.

Migration
- New scripts must land under the correct subdirectory. If legacy root paths are referenced by external tools or CI, keep a thin wrapper at `Scripts/` that delegates to the canonical path. Do not add new functional scripts at the root.

Core ML helpers (apps)
`Scripts/apps/coreml-convert.sh` bootstraps `.coremlvenv` and calls `Scripts/apps/coreml_convert.py` to produce `.mlmodel` files. Examples: `… crepe --saved-model <dir> [--frame 1024]`, `… basicpitch --saved-model <dir>`, `… keras --h5 <file.h5>`, `… tflite --tflite <file.tflite>`. Outputs default to `Public/Models/` (git‑ignored).

Curated OpenAPI
Use `Scripts/openapi/validate-curated-specs.sh` to keep `Configuration/curated-openapi-specs.json` in sync. Install local hooks once via `Scripts/install-git-hooks.sh`.

Register external OpenAPI as tools
- `Scripts/openapi/register-teatro-guide-as-tools.sh` normalizes the Teatro Prompt Field Guide OpenAPI and registers its operations via ToolsFactory. Dev‑up integration: set `REGISTER_TEATRO_GUIDE=1` to auto‑register on boot when ToolsFactory is reachable. Envs: `TOOLS_FACTORY_URL` (default `http://127.0.0.1:8011`), `TEATRO_GUIDE_CORPUS` (default `teatro-guide`), `TEATRO_GUIDE_BASE_URL` (absolute `http_path` when the spec lacks `servers[0].url`).

CI smoke for Prompt Field Guide
- `Scripts/ci/teatro-guide-smoke.sh` registers tools (idempotent), invokes one via FunctionCaller, and writes an ETag under `.fountain/artifacts/`. Inputs: `TOOLS_FACTORY_URL`, `FUNCTION_CALLER_URL`, `TEATRO_GUIDE_CORPUS`, `TEATRO_GUIDE_SPEC`, `TEATRO_GUIDE_BASE_URL` (optional; sensible defaults).
MIDI service (for Web MRTS)
- Start: `Scripts/apps/midi-service` (macOS default `coremidi`; Linux default `alsa`).
- Backends: `MIDI_SERVICE_BACKEND=coremidi|alsa|rtp|loopback`.
- Recorder (NDJSON): set `MIDI_UMP_LOG_DIR` (default `.fountain/corpus/ump`).
- OpenAPI routes:
  - UMP send/record: `POST /ump/send`, `GET /ump/events`, `POST /ump/events`.
  - Headless instruments: `GET /headless/instruments`, `POST /headless/instruments`, `DELETE /headless/instruments/{displayName}`.

Web mirror (Baseline‑PatchBay)
- Launcher: `Scripts/apps/baseline-patchbay-web` (seeds Teatro + MRTS prompts; starts Vite).
- Env: `PATCHBAY_URL`, `MIDI_SERVICE_URL`.
- Drive: set target to “PatchBay Canvas” (macOS) or “Headless Canvas” (Linux/headless) and keep “MIDI 2.0” mode with “Sync PE” on.

PatchBay docs (PB‑VRT Vision + Audio)
- Seed combined doc into FountainStore: `swift run --package-path Packages/FountainApps patchbay-docs-seed`.
- Read back: `CORPUS_ID=patchbay SEGMENT_ID='docs:pb-vrt-vision-audio:doc' swift run --package-path Packages/FountainApps store-dump`.

PB‑VRT tests (Vision + Audio)
- Run server kernel tests headless: `bash Scripts/ci/pbvrt-tests.sh`.
- Scope to a single test: `ROBOT_ONLY=1 swift test --package-path Packages/FountainApps -c debug --filter PBVRTHTTPIntegrationTests.testCompareCandidateWritesBaselineSegment`.
- Build server only: `swift build --package-path Packages/FountainApps -c debug --target pbvrt-server`.

PB‑VRT baseline seeding
- One‑shot seeder: `Scripts/apps/pbvrt-baseline-seed`
  - Seeds a prompt, creates a baseline with viewport, and captures a baseline PNG.
  - Example: `FOUNTAIN_SKIP_LAUNCHER_SIG=1 PBVRT_CORPUS_ID=pb-vrt swift run --package-path Packages/FountainApps pbvrt-server &`
    then `bash Scripts/apps/pbvrt-baseline-seed --png baseline.png --prompt-id quiet-frame-lab --server http://127.0.0.1:8010/pb-vrt --out baseline.id`.
  - Options: `--prompt-file <md>` or `--prompt-text "..."`, `--viewport WxH` (auto‑inferred with `sips`), `--renderer <ver>`.

PB‑VRT local runners
- Start server and stamp port: `bash Scripts/apps/pbvrt-up` (writes `.fountain/pb-vrt-port` and logs under `.fountain/logs/`).
- Compare candidate to baseline with thresholds: `bash Scripts/apps/pbvrt-compare-run --baseline-id $(cat baseline.id) --candidate candidate.png`.
- Generate audio WAVs (Csound or Python fallback): `bash Scripts/apps/pbvrt-audio-generate --out baseline.wav --freq 440`.
- Seed the PB‑VRT test rig prompt (Teatro): `FOUNTAIN_SKIP_LAUNCHER_SIG=1 swift run --package-path Packages/FountainApps pbvrt-rig-seed` (corpus via `CORPUS_ID`, default `patchbay`).

## Gateway — Quick Start

What
- `gateway-server` is the HTTP entrypoint that wires plugins (auth, policies, ChatKit, publishing) and serves a store‑backed agent descriptor at `/.well-known/agent-descriptor`.
- When the generated OpenAPI module is present (`gateway-service`), typed routes are registered; otherwise, fallback routes still serve the descriptor and control endpoints.

Why
- Keep descriptor provenance in FountainStore and expose a deterministic, typed surface for tools and CI. Enable fast local loops without depending on generated code.

How
- Validate a descriptor (YAML or JSON): `Scripts/tools/agent-validate agents/sample-spectralizer.yaml`
- Seed into FountainStore: `swift run --package-path Packages/FountainApps agent-descriptor-seed agents/sample-spectralizer.yaml`
- Run the gateway locally (signature skipped):
  - `FOUNTAIN_SKIP_LAUNCHER_SIG=1 GATEWAY_AGENT_ID='fountain.ai/agent/sample/spectralizer' Scripts/dev/gateway-min run`
- Probe endpoints:
  - Descriptor: `curl -s http://127.0.0.1:8010/.well-known/agent-descriptor | jq .`
  - Health/metrics: `curl -s http://127.0.0.1:8010/health`, `curl -s http://127.0.0.1:8010/metrics`

Environment
- `GATEWAY_AGENT_ID` or `AGENT_ID` — required; the agent to serve.
- `AGENT_CORPUS_ID` or `CORPUS_ID` — corpus name (default `agents`).
- `FOUNTAINSTORE_DIR` — store root (default `.fountain/store`).
- `FOUNTAIN_SKIP_LAUNCHER_SIG=1` — skips launcher signature in local dev only.

Where
- Descriptor endpoint: `Packages/FountainApps/Sources/gateway-server/GatewayServer.swift:194`
- OpenAPI generator config (gateway): `Packages/FountainApps/Sources/gateway-service/openapi-generator-config.yaml:1`
- Gateway OpenAPI spec: `Packages/FountainSpecCuration/openapi/v1/gateway.yml:1`
- Wrapper: `Scripts/dev/gateway-min:1`
- Sample descriptor: `agents/sample-spectralizer.yaml:1`
