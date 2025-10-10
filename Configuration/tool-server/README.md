# Tool Server — Human-Friendly Setup

Quick start
- Initialize config: `./Scripts/toolserver init`
- Start server: run the `tool-server` executable (build via `swift build --product tool-server`), or `./Scripts/dev-up` if you use the full stack.
- Check status: `./Scripts/toolserver status` or `./Scripts/toolserver-api status`
- Run a tool via API:
  - `./Scripts/toolserver-api imagemagick -- magick -version`
  - `./Scripts/toolserver-api exiftool -- -ver`

Files
- `docker-compose.yml`: Defines services for imagemagick, ffmpeg, exiftool, pandoc, and libplist. Healthchecks included.
- `.env.example`: Template for image overrides and pull policy.
- `.env` (generated): Created by `./Scripts/toolserver init`. Set `TOOLSERVER_WORKDIR` to the folder you want mounted at `/work`.

Environment variables
- `TOOLSERVER_WORKDIR`: Host path mounted to `/work` in containers.
- `IMAGES_PULL_POLICY`: Compose pull policy (`always`/`missing` etc.).
- `*_IMAGE`: Override image (optionally pinned by digest), e.g. `IMAGEMAGICK_IMAGE`.

Startup pull
- The `tool-server` executable will pre-pull images on startup by default. Disable with `TOOLSERVER_PULL_ON_START=0`.

Compose CLI helper
- `./Scripts/toolserver` supports:
  - `init` — generate/update `.env`
  - `pull|up|down|ps` — manage compose
  - `run <service> [args...]` — run a service directly
  - `status` — query `/_status`

API helper
- `./Scripts/toolserver-api` calls the server API for status and tool runs.

Tips
- Pin images to digests for reproducibility; set the `*_IMAGE` variables in `.env`.
- Change `TOOLSERVER_WORKDIR` to point at your project folder to operate on local files.

