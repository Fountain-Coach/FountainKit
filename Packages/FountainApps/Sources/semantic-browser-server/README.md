# Semantic Browser Service

A Swift service that fetches and renders web pages (with optional CDP headless browser), snapshots DOM+network, performs light semantic dissection into blocks/entities with span‑level offsets, and optionally persists derived artifacts into FountainStore under a corpus. Designed to be pragmatic, vendor‑neutral, and production‑ready.

## Highlights
- Snapshot: `snapshot.html` and normalized `snapshot.text` with final URL, status, content type, and timing.
- Analyze: DOM‑like segmentation (headings/paragraphs/code/tables) with stable spans into `rendered.text`, baseline entities with mention spans.
- Browse: One‑shot snapshot → analyze → optional index.
- Storage: Filesystem artifact store with TTL (no cloud lock‑in). FountainStore catalog for artifact metadata.
- Safety: API key auth, request size/time limits, SSRF allow/deny + CIDR, redirect pinning, concurrency caps (global + per‑host) with 429.
- Observability: Spec‑pure health, Prometheus metrics, admin diagnostics (browser pool, host gate, network capture, artifacts).

## API
OpenAPI spec: [`Packages/FountainSpecCuration/openapi/v1/semantic-browser.yml`](../../../FountainSpecCuration/openapi/v1/semantic-browser.yml)

Key endpoints (spec‑compliant):
- POST `/v1/snapshot` → SnapshotResponse
- POST `/v1/analyze` → Analysis
- POST `/v1/browse` → BrowseResponse (snapshot + analysis + optional index summary)
- POST `/v1/index` → IndexResult (accepts spec IndexRequest)
- GET `/v1/pages|segments|entities` → Query results
- GET `/v1/pages/{id}` → PageDoc by ID
- GET `/v1/export?pageId={sid|aid}&format=snapshot.html|snapshot.text|analysis.json|tables.csv|summary.md` → Streams artifact
- GET `/v1/health` → `{ status, version, browserPool }`

Admin and diagnostics (non‑spec):
- GET `/v1/admin/healthx` → verbose health (capture+SSRF config, hostGate stats) and runs a TTL GC pass
- GET `/v1/admin/snapshots/{snapshotId}/network` → captured request method/headers/status (CDP)
- GET `/v1/admin/artifacts?{pageId|analysisId}&kind=&limit=` → FountainStore artifact catalog search
- GET `/metrics` → Prometheus text exposition

## Request/Response Examples
Snapshot:
```bash
curl -sS -X POST http://127.0.0.1:8006/v1/snapshot \
  -H 'X-API-Key: $SB_API_KEY' -H 'Content-Type: application/json' \
  -d '{
    "url": "https://example.com",
    "wait": { "strategy": "domContentLoaded", "maxWaitMs": 3000 }
  }' | jq
```

Browse (analyze + index):
```bash
curl -sS -X POST http://127.0.0.1:8006/v1/browse \
  -H 'X-API-Key: $SB_API_KEY' -H 'Content-Type: application/json' \
  -d '{
    "url": "https://example.com",
    "wait": { "strategy": "networkIdle", "networkIdleMs": 500, "maxWaitMs": 10000 },
    "mode": "standard",
    "index": { "enabled": true }
  }' | jq '.snapshot.snapshotId,.analysis.envelope.id'
```

Export (streams stored artifact, falls back to in‑memory):
```bash
curl -sS 'http://127.0.0.1:8006/v1/export?pageId=$PAGE_OR_ANALYSIS_ID&format=analysis.json' \
  -H 'X-API-Key: $SB_API_KEY' -o analysis.json
```

## Configuration (env)
Authentication and limits:
- `SB_REQUIRE_API_KEY` (default: `true`): require `X-API-Key`
- `SB_API_KEY`: API key value for requests
- `SB_REQ_BODY_MAX_BYTES` (default: `1000000`)
- `SB_REQ_TIMEOUT_MS` (default: `15000`)
- `SB_RATE_LIMIT` (requests/minute, header‑based)

Rendering engine:
- `SB_CDP_URL`: Chrome DevTools Protocol ws:// or wss:// endpoint
- `SB_BROWSER_CLI` + `SB_BROWSER_ARGS`: external CLI renderer hook

Concurrency/backpressure:
- `SB_BROWSER_CONCURRENCY` (default: `4`)
- `SB_HOST_CONCURRENCY_PER` (default: `2`)

SSRF policy:
- `SB_URL_ALLOWLIST`, `SB_URL_DENYLIST`: hostnames (prefix `.` for suffix match)
- `SB_URL_ALLOWCIDR`, `SB_URL_DENYCIDR`: IPv4 CIDRs (e.g., `10.0.0.0/8`)

Network capture controls:
- `SB_NET_BODY_MAX_COUNT` (default: `20`)
- `SB_NET_BODY_MAX_BYTES` (default: `16384`), `SB_NET_BODY_TOTAL_MAX_BYTES` (default: `131072`)
- `SB_NET_BODY_MIME_ALLOW`: extra MIME allowlist, comma‑separated

Artifacts (filesystem store):
- `ARTIFACT_ROOT` (e.g., `/data`)
- `ARTIFACT_TTL_DAYS` (default: `7`)
- `ARTIFACT_MAX_BYTES` (optional budget)

FountainStore configuration:
- `SB_FOUNTAINSTORE_URLS` or `FOUNTAINSTORE_URLS`
- `SB_FOUNTAINSTORE_API_KEY` or `FOUNTAINSTORE_API_KEY`

## Running
Local (Swift):
```bash
swift run semantic-browser-server
```

Docker:
```bash
docker build -t semantic-browser .
# run as non-root, mount artifacts dir
docker run --rm -p 8006:8006 \
  -e SB_API_KEY=dev-key -e SB_REQUIRE_API_KEY=true \
  -e ARTIFACT_ROOT=/data -v $(pwd)/artifacts:/data \
  semantic-browser
```

## Production Tips
- Set resource limits; add liveness `/v1/health` and readiness probes.
- Pin `SB_CDP_URL` to a hardened headless Chrome if you need JS/Network capture.
- Mount `ARTIFACT_ROOT` on persistent storage; set `ARTIFACT_TTL_DAYS` per needs.
- Ensure FountainStore catalog is configured for artifact metadata querying.
- Watch `/metrics` counters: `*_requests_total/_error_total`, `*_latency_ms_*`, `artifact_*`, and pool gauges.

## Security Notes
- Always require API key (default is on). Rotate keys periodically.
- Tune SSRF allow/deny and CIDR to your org’s egress policy.
- Consider a forward proxy or egress firewall for additional control.
- Be mindful of `X-Forwarded-For` spoofing if used for rate limiting.

## Troubleshooting
- 401: missing/invalid `X-API-Key`.
- 400 (invalid_url/redirect_blocked): URL fails SSRF policy or redirect target blocked.
- 413: request body too large; adjust `SB_REQ_BODY_MAX_BYTES`.
- 429: concurrency caps hit; check `/v1/admin/healthx` pool stats; scale up or reduce traffic.
- 504 (timeout): increase `SB_REQ_TIMEOUT_MS` or reduce target page complexity.
- Exports: check `ARTIFACT_ROOT` mount and permissions; review admin health for GC activity.

## Development
- Specs live under `Packages/FountainSpecCuration/openapi/v1/semantic-browser.yml`.
- Unit tests under `Tests/SemanticBrowserTests/*` include spec conformance and query/index flows.
- Run tests: `swift test -v`

## License
See repository licenses.

