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
        WindowGroup("Blank Page") {
            BlankRootView()
        }
        .windowStyle(.automatic)
    }
}

struct BlankRootView: View {
    // Target page size in pixels
    private let pageW: CGFloat = 1024
    private let pageH: CGFloat = 1536
    private let margin: CGFloat = 40
    @State private var measuredPage: CGSize = .zero

    var body: some View {
        GeometryReader { gp in
            ZStack {
                // Slight warm background
                Color(NSColor(calibratedWhite: 0.96, alpha: 1))
                    .ignoresSafeArea()
                // Centered page scaled to fit fully visible
                let scale = min((gp.size.width - margin*2)/pageW, (gp.size.height - margin*2)/pageH)
                BlankPaper()
                    .frame(width: pageW, height: pageH)
                    .scaleEffect(scale)
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
                    .background(GeometryReader { p in
                        Color.clear.onAppear { measuredPage = p.size }
                    })
            }
        }
        .frame(minWidth: 900, minHeight: 700)
    }
}

private struct BlankPaper: View {
    var body: some View {
        ZStack {
            // Off‑white paper tone; very subtle texture via overlay noise
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(red: 0.98, green: 0.98, blue: 0.96))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        }
    }
}

