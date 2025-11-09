import XCTest
@testable import fountain_editor_service_core

final class ETagPUTTests: XCTestCase {
    func testETagPutSemantics_createUpdateGuardedByIfMatch() async throws {
        let store = InMemoryScriptStore()
        let cid = "fountain-editor"

        // No script yet: GET returns nil
        let initial = await store.get(corpusId: cid)
        XCTAssertNil(initial)

        // PUT without If-Match should be rejected (HTTP 409)
        let rejectedNoHeader = await store.put(corpusId: cid, text: "Hello", ifMatch: nil)
        XCTAssertFalse(rejectedNoHeader)

        // PUT with If-Match:"*" should create
        let created = await store.put(corpusId: cid, text: "Hello", ifMatch: "*")
        XCTAssertTrue(created)
        let afterCreate = await store.get(corpusId: cid)
        XCTAssertNotNil(afterCreate)
        let etag1 = afterCreate!.etag
        XCTAssertEqual(etag1.count, 8)

        // PUT with mismatched If-Match should be rejected
        let rejectedMismatch = await store.put(corpusId: cid, text: "Hello again", ifMatch: "deadbeef")
        XCTAssertFalse(rejectedMismatch)

        // PUT with correct If-Match should update
        let updated = await store.put(corpusId: cid, text: "Hello world!", ifMatch: etag1)
        XCTAssertTrue(updated)
        let afterUpdate = await store.get(corpusId: cid)
        XCTAssertNotNil(afterUpdate)
        XCTAssertNotEqual(afterUpdate!.etag, etag1)
    }
}

