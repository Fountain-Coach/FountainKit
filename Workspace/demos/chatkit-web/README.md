# ChatKit Web Demo

This demo mounts the ChatKit-JS widget against a running FountainKit gateway and
lets you tweak connection settings from the browser. Everything is served as
static files, so no build tooling is required.

## Prerequisites

- Swift toolchain + dependencies required to build `gateway-server`.
- `python3` (or any static file server).
- Optional: keep the bundled ChatKit sources up to date via  
  `git submodule update --remote Workspace/deps/chatkit-js`.

## One-click start

From the repository root, run:

```sh
./Workspace/demos/chatkit-web/run-demo.sh
```

The script:

1. Builds and launches `gateway-server` (port `8010` by default).
2. Hosts the demo via `python3 -m http.server` on port `8085`.
3. Opens the demo in your default browser (or prints the URL if auto-open is
   unavailable).

Press `Ctrl+C` to stop the demo; the script tears down the gateway automatically.

## Manual setup

If you prefer to run the components separately, start the gateway:

```sh
swift run --package-path Packages/FountainApps gateway-server
```

Then host the workspace (from the repo root):

```sh
python3 -m http.server 8085
```

Open <http://127.0.0.1:8085/Workspace/demos/chatkit-web/> to use the demo.

## Using the UI

- The form at the top lets you change the gateway base URL and persona. Submit
  the form to negotiate a new session.
- Query parameters `?base=` and `?persona=` pre-populate the form.
- Console logs (prefixed with `[ChatKit]`) show bootstrap status. Failures are
  also rendered inline above the widget container.

## Customising the widget

The demo imports the shared helper from `Public/chatkit.js`. If you need to test
local modifications to ChatKit-JS:

1. Update the submodule to the desired commit.
2. Rebuild or experiment in `Workspace/deps/chatkit-js/packages/chatkit`.
3. Copy the generated bundle into `Public/chatkit.js` (or adjust the import in
   `demo.js` to point at your build artifact).

Feel free to duplicate this folder for additional scenarios (e.g. multi-user
dashboards, thread explorers) – the helper takes care of session management so
you can focus on UI.
