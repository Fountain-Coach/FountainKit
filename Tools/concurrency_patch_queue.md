Concurrency + Focus Patch Queue (per-file) — FountainKit

Purpose
- Track remaining files that use pre–Swift 6 patterns (GCD, asyncAfter) or ad‑hoc focus hacks. Each entry lists the fix to apply.

Legend
- Replace GCD → `await MainActor.run { … }`
- Replace asyncAfter → `try? await Task.sleep` inside `Task { @MainActor in … }`
- Ensure focus via FocusKit or AppKit bridge + PB‑VRT test

Queue
- Packages/FountainApps/Sources/grid-dev-app/GraphOverlayMac.swift
  - Replace DispatchQueue.main.async; consider FocusKit for text inputs

Completed
- Packages/FountainApps/Sources/patchbay-app/AppMain.swift
  - Async focus paths now use `Task`/`Task.sleep`; FocusTextField + FocusManager handle first responder; remaining work is PB‑VRT focus tests for chat/editor inputs.
- Packages/FountainApps/Sources/patchbay-app/PBVRTInspector.swift
  - GCD/Task.detached replaced with `Task(priority:)` and `MainActor.run` for UI updates.
- Packages/FountainApps/Sources/engraver-studio/EngraverStudioView.swift
  - asyncAfter replaced with `Task { @MainActor in try? await Task.sleep … }` for copy toasts and focus helpers.
- Packages/FountainApps/Sources/patchbay-app/Canvas/ZoomContainer.swift
  - NSHostingView updates use `Task { @MainActor in … }` to avoid re-entrancy.
- Packages/FountainApps/Sources/patchbay-app/Canvas/EditorCanvas.swift
  - Edge glow and puff removal use `Task` + `Task.sleep` instead of `DispatchQueue.main.asyncAfter`.
- Packages/FountainApps/Sources/patchbay-app/Monitor/Midi2MonitorOverlay.swift
  - Fade scheduling uses a stored `Task` instead of `DispatchWorkItem` and GCD timers.
- Packages/FountainApps/Sources/patchbay-app/Views/FocusManager.swift
  - Focus retries and modal guard loops use `Task` + `Task.sleep` on `@MainActor` instead of GCD.
- Packages/FountainApps/Sources/MetalViewKit/MetalInstrument.swift
  - UI-bound enable/timeout paths now hop via `Task { @MainActor … }`; no `DispatchQueue.main.async` remains.
- Packages/FountainApps/Sources/FountainLauncherUI/LauncherUIApp.swift
  - Copy toasts now use `Task { @MainActor in try? await Task.sleep … }` instead of `DispatchQueue.main.asyncAfter`.
- Packages/FountainApps/Sources/qc-mock-app/ZoomScrollView.swift
  - Scroll and zoom are already driven via `Task { @MainActor … }` and AppKit events; no `DispatchQueue.main.async` remaining.
- Packages/FountainApps/Sources/grid-dev-app/AppMain.swift
  - Reset fade indicator uses a stored `Task` plus `Task.sleep` instead of `DispatchWorkItem` and GCD timers.
- Packages/FountainApps/Sources/grid-dev-app/GridDevMidiMonitorOverlay.swift
  - Overlay fade scheduling uses a stored `Task` and `Task.sleep` on `@MainActor` instead of `DispatchQueue.main.asyncAfter`.
- Packages/MemChatKit/Sources/MemChatKit/MemChatTeatroView.swift
  - Input focus is driven by SwiftUI `.focused` + `Task { @MainActor in … }`; no Dispatch/GCD usage.

Network handlers
- Packages/FountainTelemetryKit/Sources/MIDI2Transports/RTPMidiSession.swift
  - Ensure handler remains @Sendable and hops to MainActor before UI/log view updates (if any)
- Packages/FountainApps/Sources/midi-instrument-host/main.swift
  - Health server: keep UI mutations on MainActor only

Unchecked Sendable (UI targets)
- Search and remove any `@unchecked Sendable` in app/UI modules; prefer actors or value types.

CI/Lint
- Wire `Scripts/ci/lint-concurrency.sh` into CI workflows (pre-merge gate).
