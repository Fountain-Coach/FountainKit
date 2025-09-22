# Fountain Launcher UI

`FountainLauncherUI` is a macOS app that wraps the control-plane launcher scripts. It verifies the workspace layout, manages secrets in the keychain, and provides live status/console output for all Fountain services.

## Features

- Validates that the selected repository contains `Packages/FountainSpecCuration/openapi` and `Scripts/` assets before launching.
- Starts/stops the control plane via the bundled shell scripts and tails logs inside the app.
- Provides quick access to environment variables (`OPENAI_API_KEY`, `FOUNTAINSTORE_*`) and exports sanitized reports.

## Usage

Build and run via Xcode or SwiftPM:

```bash
open Packages/FountainApps/Sources/FountainLauncherUI
# or
swift run --package-path Packages/FountainApps FountainLauncherUI
```

Because the app targets macOS, a GUI environment is required.
