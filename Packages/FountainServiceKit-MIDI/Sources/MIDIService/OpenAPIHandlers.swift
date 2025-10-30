import Foundation
import OpenAPIRuntime

// Stubs for generated server protocol will be extended as needed.
// This file compiles even before generation and will be augmented by the plugin.

public enum MIDIServiceImpl {
    public static func healthResponse() throws -> (status: String, uptimeSec: Double) {
        (status: "ok", uptimeSec: ProcessInfo.processInfo.systemUptime)
    }
}

