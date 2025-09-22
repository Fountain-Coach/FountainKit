import Foundation
import Dispatch

enum Timing {
    private static let startUptime = DispatchTime.now().uptimeNanoseconds
    private static let startHost = Date().timeIntervalSince1970

    static func jrNow() -> Double {
        let us = (DispatchTime.now().uptimeNanoseconds &- startUptime) / 1_000
        return Double(us)
    }

    static func hostTime(fromJR ts: Double) -> Double {
        return startHost + ts / 1_000_000
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
