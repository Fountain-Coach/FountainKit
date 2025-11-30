import Foundation
import JavaScriptCore

/// Minimal JSCore bridge placeholder for midi2.js integration.
/// Loads a tiny JS harness to confirm JSContext availability and to expose a future `scheduleUMP` hook.
final class Midi2JSBridge {
    private let context: JSContext
    private let bundlePath: String?
    private(set) var bundleLoaded: Bool = false

    init?(bundlePath: String? = nil) {
        guard let ctx = JSContext() else { return nil }
        self.context = ctx
        self.bundlePath = bundlePath
        injectHarness()
        if let bundlePath {
            loadBundle(at: bundlePath)
        } else if let defaultBundle = Self.defaultBundlePath() {
            loadBundle(at: defaultBundle)
        }
    }

    /// Attempt to load a midi2.js bundle from disk and evaluate it in the JSContext.
    /// - Parameter bundlePath: path to a JS bundle (e.g., bundled midi2.js build) to load.
    func loadBundle(at bundlePath: String) {
        let url = URL(fileURLWithPath: bundlePath)
        guard let data = try? Data(contentsOf: url), let script = String(data: data, encoding: .utf8) else { return }
        _ = context.evaluateScript(script)
        bundleLoaded = true
    }

    private func injectHarness() {
        // Simple harness: collect scheduled UMPs into an in-memory log for debugging/tests.
        let script = """
        var midi2 = {
          log: [],
          scheduleUMP: function(bytes, ts) { midi2.log.push({ bytes: bytes, ts: ts }); return true; },
          capabilities: function() { return { version: "0.1", scheduler: "js-core-stub" }; },
          logSize: function() { return midi2.log.length; }
        };
        """
        _ = context.evaluateScript(script)
    }

    func capabilities() -> [String: Any] {
        guard let caps = context.objectForKeyedSubscript("midi2")?.invokeMethod("capabilities", withArguments: []) else {
            return [:]
        }
        return caps.toDictionary() as? [String: Any] ?? [:]
    }

    @discardableResult
    func scheduleUMP(bytes: [UInt8], timestamp: UInt64) -> Bool {
        guard let midi2 = context.objectForKeyedSubscript("midi2") else { return false }
        let array = JSValue(object: bytes, in: context)
        let ts = JSValue(double: Double(timestamp), in: context)
        let res = midi2.invokeMethod("scheduleUMP", withArguments: [array as Any, ts as Any])
        return res?.toBool() ?? false
    }

    func logSize() -> Int {
        guard let midi2 = context.objectForKeyedSubscript("midi2"),
              let res = midi2.invokeMethod("logSize", withArguments: []) else { return 0 }
        return Int(res.toInt32())
    }

    private static func defaultBundlePath() -> String? {
        let candidates = [
            "Public/midi2-browser/vendor/midi2/dist/midi2.js",
            "Public/midi2-browser/vendor/midi2/dist/midi2.umd.js",
            "Public/midi2-browser/vendor/midi2/dist/index.js",
            "Public/midi2-browser/vendor/midi2/dist/index.cjs"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
}
