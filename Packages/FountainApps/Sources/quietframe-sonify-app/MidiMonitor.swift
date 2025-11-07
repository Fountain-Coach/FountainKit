import Foundation
import SwiftUI

@MainActor final class MidiMonitorStore: ObservableObject {
    static let shared = MidiMonitorStore()
    @Published var events: [String] = []
    private let maxEvents = 100
    func add(_ s: String) {
        events.append(s)
        if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }
    }
    func clear() { events.removeAll() }
}

struct MidiMonitorHUD: View {
    @ObservedObject var store: MidiMonitorStore = .shared
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("MIDI Monitor").font(.caption).bold()
                Spacer()
                Button("Clear") { store.clear() }.font(.caption2)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(store.events.suffix(12)).enumerated().map { $0 }, id: \.offset) { _, line in
                        Text(line).font(.caption2).monospaced().foregroundStyle(.secondary)
                    }
                }
            }.frame(height: 120)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

