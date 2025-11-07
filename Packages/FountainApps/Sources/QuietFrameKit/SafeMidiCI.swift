import Foundation
import MIDI2
import MIDI2CI

public enum SafeMidiCI {
    /// Returns a MIDI-CI envelope iff the SysEx7 payload looks like a valid Universal MIDI-CI frame.
    /// Performs strict header and length checks before invoking the library initializer
    /// to avoid precondition traps on malformed frames.
    public static func decode(sysEx7 bytes: [UInt8]) -> MidiCiEnvelope? {
        // Minimal validity: F0 ... F7
        guard bytes.count >= 7, bytes.first == 0xF0, bytes.last == 0xF7 else { return nil }
        // Universal (Non-RT or RT)
        let manuf = bytes[1]
        guard manuf == 0x7E || manuf == 0x7F else { return nil }
        // SubID#1 for MIDI-CI (0x0D)
        // Layout: F0 7E/7F <deviceId> 0x0D <subId2> ... F7
        guard bytes[3] == 0x0D else { return nil }
        // Basic structural sanity: ensure subId2 exists
        guard bytes.count >= 6 else { return nil }
        // Defer to library only after guards to avoid crash
        return try? MidiCiEnvelope(sysEx7Payload: bytes)
    }
}
