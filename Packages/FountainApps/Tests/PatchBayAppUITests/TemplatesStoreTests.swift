import XCTest
@testable import patchbay_app

@MainActor
final class TemplatesStoreTests: XCTestCase {
    func testLoadReseedsOnEmptyOrAllHidden() {
        let store = InstrumentTemplatesStore()
        // Backup any previous value
        let key = "pb.templates"
        let backup = UserDefaults.standard.data(forKey: key)
        defer { UserDefaults.standard.set(backup, forKey: key) }

        // Case 1: Corrupt or empty array
        UserDefaults.standard.set(Data("[]".utf8), forKey: key)
        var items = store.load()
        XCTAssertGreaterThanOrEqual(items.count, 4)

        // Case 2: All hidden persisted
        for i in 0..<items.count { items[i].hidden = true }
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key) }
        let loaded = store.load()
        XCTAssertTrue(loaded.contains(where: { !$0.hidden }), "Reseed defaults when all hidden")
    }
}

