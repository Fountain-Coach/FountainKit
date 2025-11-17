import SwiftUI
import AppKit

@main
struct BlankPageApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    var body: some Scene {
        WindowGroup("Blank Page") { BlankRootView() }
            .windowStyle(.automatic)
    }
}

struct BlankRootView: View {
    private let pageW: CGFloat = 1024
    private let pageH: CGFloat = 1536
    private let margin: CGFloat = 40
    var body: some View {
        GeometryReader { gp in
            ZStack {
                Color(NSColor(calibratedRed: 0.97, green: 0.97, blue: 0.98, alpha: 1)).ignoresSafeArea()
                let scale = min((gp.size.width - margin*2)/pageW, (gp.size.height - margin*2)/pageH)
                ZStack {
                    if let url = Bundle.module.url(forResource: "blank-paper-1024x1536", withExtension: "png"),
                       let nsImg = NSImage(contentsOf: url) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                    } else {
                        // Fallback vector paper if PNG not present
                        BlankPaper()
                    }
                }
                .frame(width: pageW, height: pageH)
                .scaleEffect(scale)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
            }
        }
        .frame(minWidth: 900, minHeight: 700)
    }
}

private struct BlankPaper: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(red: 0.98, green: 0.98, blue: 0.96))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        }
    }
}
