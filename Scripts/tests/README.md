# Scripts/tests — Manual Smoke Tests

This directory contains optional end‑to‑end smoke tests that exercise the
running services. They are not part of CI and should be run manually.

## readability-smoke.sh

Boots a temporary `persist-server` on a test port, points it to a temporary
`.fountain` file, and probes the Speech Atlas `/speeches/script` endpoint.

Requirements: `swift`, `curl`, `jq` (and optionally `wkhtmltopdf` for PDF flows).

Usage:

```
Scripts/tests/readability-smoke.sh [--port <n>] [--keep]
```

What it does:
- Builds `persist-server`
- Generates a sample `.fountain` with ACT I / SCENE II
- Starts the server with `FOUNTAIN_SOURCE_PATH` pointing at the sample
- Waits for readiness and verifies:
  - `/speeches/script` returns a header starting with `Act I Scene II`
  - The first JSON block speaker is `CELIA` for `layout=screenplay`

Use `--keep` to preserve the temp directory and logs for inspection.

