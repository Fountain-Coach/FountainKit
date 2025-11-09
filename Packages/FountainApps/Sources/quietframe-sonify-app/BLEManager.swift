import Foundation
import SwiftUI
import MetalViewKit

@MainActor final class BLEManager: ObservableObject {
    enum Mode: String, Identifiable { case central; var id: String { rawValue } }
    @Published var mode: Mode = .central
    @Published var targetNameSubstr: String = ""
    @Published var advertisedName: String = "QuietFrame"
    @Published var status: String = "central"

    private weak var instrument: MetalInstrument?
    init(instrument: MetalInstrument?) { self.instrument = instrument }

    func apply() {
        guard let inst = instrument else { return }
        // Disable current session, swap transport, re-enable (central only)
        inst.disable()
        let name = targetNameSubstr.isEmpty ? nil : targetNameSubstr
        MetalInstrument.setDefaultTransport(MIDI2SystemInstrumentTransport(backend: .ble(name)))
        status = name ?? "central"
        BLEFacts.shared.set(mode: "central")
        if let n = name { BLEFacts.shared.set(key: "target.name", n) }
        inst.enable()
    }
}
