import Foundation

// Pure mapping helpers for tests and UI
enum MPEPadMapping {
    // Map normalized X in [0,1] to 14-bit pitch bend value [0,16383], center ≈ 8192
    static func pitchBend14(x: Double) -> UInt16 {
        let clamped = max(0.0, min(1.0, x))
        let centered = clamped - 0.5 // [-0.5, +0.5]
        let value = 8192.0 + centered * 16383.0
        let iv = Int(round(value))
        return UInt16(max(0, min(16383, iv)))
    }
    // Map normalized Y in [0,1] to velocity [20..127]
    static func velocity(y: Double) -> UInt8 {
        let clamped = max(0.0, min(1.0, y))
        let v = 20.0 + clamped * 107.0
        let iv = Int(round(v))
        return UInt8(max(0, min(127, iv)))
    }
    // Generate RPN 0,0 (Pitch Bend Sensitivity) messages for a single channel with given semitones
    // Returns sequence of (controller, value) pairs in order
    static func rpnPitchBendSensitivity(semitones: UInt8) -> [(UInt8, UInt8)] {
        return [
            (101, 0),    // RPN MSB = 0
            (100, 0),    // RPN LSB = 0
            (6, semitones), // Data Entry MSB = semitones
            (38, 0),     // Data Entry LSB = 0
            (101, 127),  // RPN null
            (100, 127)   // RPN null
        ]
    }
}

