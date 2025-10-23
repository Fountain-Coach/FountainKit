# AGENT — Scripts/ci (smoke tests and helpers)

Scope: `Scripts/ci/**`.

Purpose
- Keep CI‑oriented scripts (smoke tests, status probes) separate from developer tooling.

Included tools
- `ci-smoke.sh` — Brings up core services with readiness checks; probes metrics; tears down.
- `ci-toolserver-smoke.sh` — Optional smoke for tool-server when `CI_TOOLSERVER_SMOKE=1`.

Usage
- Workspace smoke: `bash Scripts/ci/ci-smoke.sh`
- Toolserver smoke: `CI_TOOLSERVER_SMOKE=1 bash Scripts/ci/ci-toolserver-smoke.sh`

Compatibility
- Legacy wrappers remain at `Scripts/ci-smoke.sh` and `Scripts/ci-toolserver-smoke.sh` and delegate to these canonical paths.

