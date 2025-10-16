# Teatro Shim

This directory contains lightweight shims for the Teatro packages that FountainKit
expects in local development. The real Teatro repository is large and not yet vendored
into this workspace; the stub packages provide just enough API surface to build and
exercise the gateway server while the generated-server migration is underway.

- `Packages/TeatroCore` exposes a minimal `FountainParser` and `FountainNode` so
  persistence tooling can compile.
- `Packages/TeatroGUI` offers simplified SwiftUI views used by Engraver Studio.

When the upstream Teatro packages become available, replace these shims with the
official sources or add the repository as a proper dependency.
