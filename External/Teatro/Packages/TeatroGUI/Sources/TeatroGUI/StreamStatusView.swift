#if canImport(SwiftUI)
import SwiftUI

/// Minimal connection status banner that mirrors the API surface expected
/// by EngraverStudio while the real TeatroGUI dependency is unavailable.
public struct StreamStatusView: View {
    private let connected: Bool
    private let acks: Int
    private let nacks: Int
    private let rtt: Int
    private let window: Int
    private let loss: Int

    public init(
        connected: Bool,
        acks: Int,
        nacks: Int,
        rtt: Int,
        window: Int,
        loss: Int
    ) {
        self.connected = connected
        self.acks = acks
        self.nacks = nacks
        self.rtt = rtt
        self.window = window
        self.loss = loss
    }

    public var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(connected ? Color.green : Color.red)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            statusMetric(label: "ACKs", value: acks)
            statusMetric(label: "NACKs", value: nacks)
            statusMetric(label: "RTT", value: rtt, suffix: "ms")
            statusMetric(label: "Window", value: window)
            statusMetric(label: "Loss", value: loss, suffix: "%")

            Spacer()
        }
        .font(.caption)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    private func statusMetric(label: String, value: Int, suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            Text("\(value)\(suffix)")
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
}
#endif
