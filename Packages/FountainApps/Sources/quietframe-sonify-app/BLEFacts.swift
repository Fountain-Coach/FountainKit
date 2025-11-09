import Foundation

@MainActor final class BLEFacts {
    static let shared = BLEFacts()
    private init() {}
    private var values: [String: Any] = ["mode":"off"]
    func set(key: String, _ value: Any) { values[key] = value }
    func set(mode: String) { values["mode"] = mode }
    func snapshot() -> [String: Any] { values }
}

