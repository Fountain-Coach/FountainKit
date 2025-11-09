import Foundation
import FountainStoreClient
import Yams

struct Part: Decodable { let name: String?; let channel: Int?; let dest: String? }
struct OrchestraDoc: Decodable { let orchestra: Orchestra? }
struct Orchestra: Decodable { let name: String?; let parts: [Part]? }

@main
struct QuietFrameOrchestraGenerate {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let corpusId = env["CORPUS_ID"] ?? "quietframe"
        let storeDir = env["FOUNTAINSTORE_DIR"] ?? ".fountain/store"
        let partitureId = env["PARTITURE_PAGE_ID"] ?? "docs:quietframe:orchestra-default:doc"
        let sourceName = env["SOURCE_NAME"] ?? "QuietFrame (local)"

        // Init store client
        let root = URL(fileURLWithPath: storeDir)
        let client: FountainStoreClient
        do { client = FountainStoreClient(client: try DiskFountainStoreClient(rootDirectory: root)) }
        catch { fprint("error: cannot init store: \(error)"); return }

        // Fetch YAML text (segment stores JSON wrapper; read text field if present)
        guard let raw = try? await client.getDoc(corpusId: corpusId, collection: "segments", id: partitureId) else { fprint("error: partiture segment not found: \(partitureId)"); return }
        let text: String
        if let outer = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any], let t = outer["text"] as? String { text = t } else if let s = String(data: raw, encoding: .utf8) { text = s } else { fprint("error: cannot decode partiture text"); return }

        // Parse YAML
        let decoder = YAMLDecoder()
        let doc: OrchestraDoc
        do { doc = try decoder.decode(OrchestraDoc.self, from: text) } catch { fprint("error: YAML parse failed: \(error)"); return }
        let parts = doc.orchestra?.parts ?? []

        // Build destinations set and routes
        var destsOrdered: [String] = []
        var destIndex: [String: Int] = [:]
        func colIndex(for dest: String) -> Int {
            if let i = destIndex[dest] { return i }
            destIndex[dest] = destsOrdered.count
            destsOrdered.append(dest)
            return destsOrdered.count - 1
        }

        var routes: [[String: Any]] = []
        for p in parts {
            guard let ch = p.channel, ch >= 1, ch <= 16 else { continue }
            let dest = (p.dest ?? destsOrdered.first ?? "BLE: iPad")
            let col = colIndex(for: dest)
            let route: [String: Any] = [
                "row": 0,
                "col": col,
                "group": 0,
                "channelMask": [ch],
                "filters": ["cv2": 1, "m1": 1, "pe": 1, "utility": 1]
            ]
            routes.append(route)
        }

        let obj: [String: Any] = [
            "sources": [sourceName],
            "destinations": destsOrdered,
            "routes": routes
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]), let textOut = String(data: data, encoding: .utf8) else { fprint("error: failed to encode blueprint"); return }
        // Write to routing blueprint segment
        let segment = Segment(corpusId: corpusId, segmentId: "prompt:quietframe-routing:routes", pageId: "prompt:quietframe-routing", kind: "facts", text: textOut)
        _ = try? await client.addSegment(segment)
        fprint("Generated routes: sources=\([sourceName]) dests=\(destsOrdered.count) routes=\(routes.count)")

        // Optional: write a small plan doc
        let planText = """
        Orchestration Plan (auto)
        - Source: \(sourceName)
        - Destinations: \(destsOrdered.joined(separator: ", "))
        - Routes: \(routes.count) part(s) mapped by channel from Partiture
        """
        _ = try? await client.addSegment(.init(corpusId: corpusId, segmentId: "docs:quietframe:orchestra-plan:doc", pageId: "docs:quietframe:orchestra-plan", kind: "doc", text: planText))
    }

    static func fprint(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
}

