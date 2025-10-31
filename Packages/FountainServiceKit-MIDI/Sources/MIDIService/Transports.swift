import Foundation
import MIDI2Transports

enum MIDISendError: Error { case unsupportedTransport, destinationNotFound }

@MainActor
final class SimpleMIDISender {
    #if canImport(CoreMIDI)
    private static var transports: [String: Any] = [:] // name -> CoreMIDITransport
    #endif

    static func listDestinationNames() -> [String] {
        #if canImport(CoreMIDI)
        return CoreMIDITransport.destinationNames()
        #else
        return []
        #endif
    }

    static func send(words: [UInt32], toDisplayName name: String?) throws {
        #if canImport(CoreMIDI)
        let key = name ?? "__first__"
        let transport: CoreMIDITransport
        if let existing = transports[key] as? CoreMIDITransport {
            transport = existing
        } else {
            transport = CoreMIDITransport(name: "midi-service", destinationName: name, enableVirtualEndpoints: false)
            try transport.open()
            transports[key] = transport
        }
        try transport.send(umpWords: words)
        #else
        throw MIDISendError.unsupportedTransport
        #endif
    }
}
