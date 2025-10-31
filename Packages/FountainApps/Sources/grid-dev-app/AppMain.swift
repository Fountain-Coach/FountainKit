import SwiftUI
import MetalViewKit
import LauncherSignature
import FountainStoreClient

@main
struct GridDevApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup("Grid Dev") {
            GridDevView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.expanded)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }
        Task.detached {
            // Seed & print prompt on boot (policy)
            let prompt = await GridDevApp.buildTeatroPrompt()
            await PromptSeeder.seedAndPrint(appId: "grid-dev", prompt: prompt, facts: [
                "instruments": [[
                    "manufacturer": "Fountain",
                    "product": "GridDev",
                    "instanceId": "grid-dev-1",
                    "displayName": "Grid Dev"
                ],[
                    "manufacturer": "Fountain",
                    "product": "Cursor",
                    "instanceId": "grid-cursor",
                    "displayName": "Grid Cursor"
                ]]
            ])
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class GridVM: ObservableObject {
    @Published var zoom: CGFloat = 1.0
    @Published var translation: CGPoint = .zero
    @Published var grid: Int = 24
    @Published var majorEvery: Int = 5
}

struct GridDevView: View {
    @StateObject private var vm = GridVM()
    var body: some View {
        let content = ZStack(alignment: .topLeading) {
            MetalCanvasView(
                zoom: vm.zoom,
                translation: vm.translation,
                gridMinor: CGFloat(vm.grid),
                majorEvery: vm.majorEvery,
                nodes: { [] },
                edges: { [] },
                selected: { [] },
                onSelect: { _ in },
                onMoveBy: { _,_ in },
                onTransformChanged: { t, z in vm.translation = t; vm.zoom = z },
                instrument: MetalInstrumentDescriptor(
                    manufacturer: "Fountain",
                    product: "GridDev",
                    instanceId: "grid-dev-1",
                    displayName: "Grid Dev"
                )
            )
            .ignoresSafeArea()

            Text(String(format: "Zoom %.2fx  Origin (%.0f, %.0f)", Double(vm.zoom), vm.translation.x, vm.translation.y))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
                .padding(8)
                .allowsHitTesting(false)
        }
        // Overlays
        content
            // MIDI monitor pinned to top-right (non-interactive)
            .overlay(alignment: .topTrailing) {
                GridDevMidiMonitorOverlay(isHot: .constant(true))
                    .padding(8)
                    .allowsHitTesting(false)
            }
            // Reset grid button (top-left below zoom badge)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Spacer().frame(height: 32)
                    Button {
                        NotificationCenter.default.post(
                            name: Notification.Name("MetalCanvasRendererCommand"),
                            object: nil,
                            userInfo: ["op": "set", "zoom": 1.0, "tx": 0.0, "ty": 0.0]
                        )
                    } label: {
                        Text("Reset Grid").font(.system(size: 11, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.leading, 6)
                .padding(.top, 6)
            }
        .frame(minWidth: 800, minHeight: 600)
    }
}

extension GridDevApp {
    @MainActor static func buildTeatroPrompt() -> String {
        return """
        Scene: GridDevApp (Grid‑Only with Persistent Corpus)
        Text:
        - Window: macOS titlebar window, 1440×900pt. Content background white (#FAFBFD).
        - Layout: single full‑bleed canvas; no sidebar, no extra panes, minimal chrome.
        - Only view: “Grid” Instrument filling the content.
          - Grid anchoring: viewport‑anchored. Leftmost vertical line renders at view.x = 0 across all translations/zoom. Topmost horizontal line at view.y = 0.
          - Minor spacing: 24 pt; Major every 5 minors (120 pt). Minor #ECEEF3, Major #D1D6E0. Crisp 1 px.
          - Axes: Doc‑anchored origin lines (x=0/y=0) in faint red (#BF3434) for orientation.
          - Overlay top‑left: “Zoom 1.00x  Origin (0, 0)” (SF Mono 11, capsule #EEF2F7, text #6B7280). Non‑interactive.
        - MIDI 2.0 Monitor pinned top‑right (non‑interactive).
        - Cursor Instrument (always on): crosshair + ring + tiny “0” rendered at the pointer; label offset so it never occludes the zero.
          - Grid coordinates: g: col,row where
            • doc = (view/zoom) − translation
            • leftDoc = 0/zoom − tx, topDoc = 0/zoom − ty
            • col = round((doc.x − leftDoc)/step), row = round((doc.y − topDoc)/step)
            • step = grid.minor
        """
    }
}
