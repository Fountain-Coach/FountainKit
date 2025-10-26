import XCTest
import Yams

final class SpecBasicsTests: XCTestCase {
    func testEndpointsPresent() throws {
        let url = URL(fileURLWithPath: "Packages/FountainApps/Sources/qc-mock-service/openapi.yaml")
        let data = try Data(contentsOf: url)
        let yaml = try Yams.load(yaml: String(decoding: data, as: UTF8.self))
        guard let root = yaml as? [String: Any], let paths = root["paths"] as? [String: Any] else {
            XCTFail("Invalid OpenAPI root/paths"); return
        }
        // Required endpoints
        XCTAssertNotNil(paths["/health"])      
        XCTAssertNotNil(paths["/canvas"])      
        XCTAssertNotNil(paths["/canvas/zoom/fit"]) 
        XCTAssertNotNil(paths["/canvas/zoom/actual"]) 
        XCTAssertNotNil(paths["/canvas/zoom"])  
        XCTAssertNotNil(paths["/canvas/pan"])   
        XCTAssertNotNil(paths["/nodes"])       
        XCTAssertNotNil(paths["/edges"])       
        XCTAssertNotNil(paths["/export/json"]) 
        XCTAssertNotNil(paths["/export/dsl"])  
        XCTAssertNotNil(paths["/import/json"]) 
        XCTAssertNotNil(paths["/import/dsl"])  
    }
    func testSchemasPresent() throws {
        let url = URL(fileURLWithPath: "Packages/FountainApps/Sources/qc-mock-service/openapi.yaml")
        let data = try Data(contentsOf: url)
        let yaml = try Yams.load(yaml: String(decoding: data, as: UTF8.self))
        guard let root = yaml as? [String: Any], let comps = root["components"] as? [String: Any], let schemas = comps["schemas"] as? [String: Any] else {
            XCTFail("Invalid OpenAPI components/schemas"); return
        }
        for key in ["CanvasState","CanvasTransform","CanvasPatch","Node","Port","Edge","GraphDoc","PatchNode","CreateNode","CreateEdge"] {
            XCTAssertNotNil(schemas[key], "Missing schema \(key)")
        }
    }
}

