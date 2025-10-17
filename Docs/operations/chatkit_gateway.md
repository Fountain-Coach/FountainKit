# ChatKit Gateway Operations

This guide summarizes the operational levers for the ChatKit gateway executable that lives in `Packages/FountainApps/Sources/gateway-server`.

## Configuration surface

The gateway reads attachment controls from process environment variables when booting. All knobs are optional; defaults mirror the values baked into `ChatKitConfig`.

| Variable | Default | Description |
| --- | --- | --- |
| `CHATKIT_ATTACHMENT_MAX_MB` | `25` | Maximum attachment payload size accepted by the upload handler. Values greater than zero are converted to bytes; non-positive/invalid input reverts to the default. |
| `CHATKIT_ATTACHMENT_ALLOWED_MIME_TYPES` | `image/png,image/jpeg,image/webp,image/gif,application/pdf,text/plain,application/json,application/octet-stream` | Comma and whitespace separated allowlist. Values are lowercased and trimmed before enforcement. |
| `CHATKIT_ATTACHMENT_TTL_HOURS` | `24` | Retention window for stored attachments and metadata. The cleanup worker deletes anything older than this TTL. |
| `CHATKIT_ATTACHMENT_CLEANUP_INTERVAL_MINUTES` | `15` | Period used by `AttachmentCleanupJob.scheduleRecurring` to re-run the TTL sweep. Set to `0` to disable the recurring task. |
| `CHATKIT_ATTACHMENT_CLEANUP_BATCH_SIZE` | `100` | Maximum number of attachment documents scanned per batch while sweeping the corpus. Increasing this speeds up purges at the cost of higher load on FountainStore. |
| `CHATKIT_UPLOAD_ROOT` | Derived from Application Support or `/tmp` | Overrides the local disk directory used by `ChatKitUploadStore` when no explicit `FountainStoreClient` is provided. Useful for development sandboxes or when mounting persistent volumes. |

## Logging

`ChatKitLogging` ships structured JSON events for uploads, downloads, and cleanup sweeps. Forward the process stdout stream into your observability stack to monitor attachment activity and capture failure diagnostics (`level`, `code`, `message`).

## Health checks

- Ensure `AttachmentCleanupJob` is running by confirming logs emit `attachmentCleanup` events at the expected cadence.
- Track upload rejections by monitoring `attachmentUploadFailed` events; repeated `413`/`payload_too_large` statuses usually indicate the maximum size is misconfigured between clients and the gateway.
- When enabling streaming, validate that downstream SSE consumers observe `delta` events and final `done` markers—mismatched proxy buffers can strip the `text/event-stream` content type.

## Publishing frontend

- The bundled frontend lives in `Public/` and consists of `index.html`, `styles.css`, and `chatkit.js`. The HTML document loads the official ChatKit-JS bundle from the CDN (`https://cdn.openai.com/chatkit/v1/chatkit.umd.js`) and delegates session bootstrap to the local `/chatkit/session` endpoint.
- Override `PUBLISHING_STATIC_ROOT` when deploying the gateway from a different working directory, ensuring the publishing plugin resolves to the directory containing the ChatKit assets.
- Open the browser console to inspect bootstrap logs; the `chatkit.js` helper prints success and failure messages as it negotiates sessions with the gateway.
- The upstream widget sources are mirrored as a git submodule in `Workspace/deps/chatkit-js`. Pull the latest changes with `git submodule update --remote Workspace/deps/chatkit-js` before rebuilding or linting the local bundle.
- For manual QA, use the plain web demo under `Workspace/demos/chatkit-web` (`./Workspace/demos/chatkit-web/run-demo.sh` starts both the gateway and static server; `Ctrl+C` stops them).
- To disable automatic bootstrap when embedding the helper into your own pages, set `window.chatkitConfig = { auto: false, … }` before importing `Public/chatkit.js` and call `bootstrapChatKit` manually.
