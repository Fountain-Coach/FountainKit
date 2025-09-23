# Toolsmith Agent Guide

## VM-first execution model
- Toolsmith must hydrate the manifest-defined VM image before use. Download the artifact into `.toolsmith/cache/<image>/<version>` and verify its SHA-256 digest prior to boot.
- Cache hydrated images; skip re-download when the digest matches the manifest.
- Boot the VM on demand when a task switches into VM execution mode. Mount the shared workspace filesystem read-only by default with an opt-in write-through channel for artifact export.
- Maintain a command channel between host and guest for dispatching tool invocations, status streaming, and graceful shutdown signals.
- Expose execution toggles via environment variables such as `TOOLSMITH_EXECUTION=host|vm` and per-command overrides, defaulting to VM-backed runs.

## Coding and testing standards
- Format Swift sources with `swift format --in-place` (or `swift-format` tooling adopted by the repository) before committing.
- Run `swift build` at the workspace root to ensure the package graph remains valid.
- Add or update focused tests via `swift test --filter` or `swift test --test-case` for modules touched by VM integration.
- Primary integration points live in `Sources/Toolsmith/Toolsmith.swift`, virtualization backend implementations under `Sources/Toolsmith/Virtualization/`, and adapter bridges in `Sources/Toolsmith/Adapters/`. Update these when evolving the VM lifecycle.

## Documentation and observability
- Update user-facing documentation (README, integration guides) whenever the VM execution model changes defaults or configuration options.
- Enhance logging to differentiate host vs VM execution paths, ensuring telemetry captures download, verification, boot, and teardown events.
- Provide verification steps so adopters can confirm VM-backed execution is active, including sample log excerpts and troubleshooting tips.
