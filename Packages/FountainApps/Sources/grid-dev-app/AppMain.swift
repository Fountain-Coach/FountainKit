import SwiftUI
import MetalViewKit
import LauncherSignature

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
        ZStack(alignment: .topLeading) {
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
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}
