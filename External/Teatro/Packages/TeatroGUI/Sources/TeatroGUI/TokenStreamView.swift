#if canImport(SwiftUI)
import SwiftUI

/// Lightweight stand-in for the Teatro token stream visualisation.
/// Provides a minimal SwiftUI representation so that dependent apps
/// can build without the full TeatroGUI package.
public struct TokenStreamView: View {
    private let tokens: [String]
    private let showBeatGrid: Bool

    public init(tokens: [String], showBeatGrid: Bool = false) {
        self.tokens = tokens
        self.showBeatGrid = showBeatGrid
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { entry in
                    Text(entry.element)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(rowBackground(for: entry.offset))
                }
            }
            .padding(showBeatGrid ? 4 : 0)
        }
    }

    private func rowBackground(for index: Int) -> Color {
        if showBeatGrid && index.isMultiple(of: 2) {
            return Color.accentColor.opacity(0.05)
        } else {
            return Color.clear
        }
    }
}
#endif
