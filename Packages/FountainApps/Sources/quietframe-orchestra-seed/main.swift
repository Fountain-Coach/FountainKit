import Foundation
import FountainStoreClient

@main
struct QuietFrameOrchestraSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let corpusId = env["CORPUS_ID"] ?? "quietframe"
        let bleName = env["AUM_BLE_NAME"] ?? "iPad"
        let rtpTargets = (env["AUM_RTP_TARGETS"] ?? "").split(separator: ",").map { String($0) }
        let root = URL(fileURLWithPath: env["FOUNTAINSTORE_DIR"] ?? ".fountain/store")
        let client: FountainStoreClient
        do { client = FountainStoreClient(client: try DiskFountainStoreClient(rootDirectory: root)) }
        catch { print("seed: failed to init DiskFountainStoreClient: \(error)"); return }
        do { _ = try await client.createCorpus(corpusId, metadata: ["app": "quietframe", "kind": "orchestra"]) } catch { }

        // Partiture YAML (default orchestra mapping for AUM + AudioLayer)
        let pageId = "docs:quietframe:orchestra-default"
        _ = try? await client.addPage(.init(corpusId: corpusId, pageId: pageId, url: "store://docs/quietframe/orchestra-default", host: "store", title: "Orchestra Mapping — Default (AUM/AudioLayer)"))
        let yaml = """
        version: 1
        target:
          kind: aum
          plugin: AudioLayer
          endpoints:
            - ble: \(bleName)
            # Optional RTP peers (host:port)
            # - rtp: 192.168.1.42:5868
        orchestra:
          name: Default
          parts:
            # Strings (channels 1–5)
            - name: Violins I   \n  channel: 1   \n  dest: BLE: \(bleName)
            - name: Violins II  \n  channel: 2   \n  dest: BLE: \(bleName)
            - name: Violas      \n  channel: 3   \n  dest: BLE: \(bleName)
            - name: Cellos      \n  channel: 4   \n  dest: BLE: \(bleName)
            - name: Basses      \n  channel: 5   \n  dest: BLE: \(bleName)
            # Woodwinds (channels 6–9)
            - name: Flute       \n  channel: 6   \n  dest: BLE: \(bleName)
            - name: Oboe        \n  channel: 7   \n  dest: BLE: \(bleName)
            - name: Clarinet    \n  channel: 8   \n  dest: BLE: \(bleName)
            - name: Bassoon     \n  channel: 9   \n  dest: BLE: \(bleName)
            # Percussion (channel 10)
            - name: Percussion  \n  channel: 10  \n  dest: BLE: \(bleName)
            # Brass (channels 11–14)
            - name: Horns       \n  channel: 11  \n  dest: BLE: \(bleName)
            - name: Trumpets    \n  channel: 12  \n  dest: BLE: \(bleName)
            - name: Trombones   \n  channel: 13  \n  dest: BLE: \(bleName)
            - name: Tuba        \n  channel: 14  \n  dest: BLE: \(bleName)
            # Aux (channels 15–16)
            - name: Harp        \n  channel: 15  \n  dest: BLE: \(bleName)
            - name: Piano       \n  channel: 16  \n  dest: BLE: \(bleName)
        notes:
          - Each part maps to a MIDI 1.0 channel on the AudioLayer instance in AUM.
          - The historical in-app routing panel was removed; routing is now generated as a Store blueprint for reference.
          - Use the BLE target env (QF_BLE_TARGET) for default routing; RTP peers can be driven by dedicated tools.
          - See docs:quietframe:orchestra-howto:doc for step-by-step usage.
        """
        _ = try? await client.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):doc", pageId: pageId, kind: "doc", text: yaml))

        // HOWTO documentation (linked by the Partiture)
        let howtoPage = "docs:quietframe:orchestra-howto"
        _ = try? await client.addPage(.init(corpusId: corpusId, pageId: howtoPage, url: "store://docs/quietframe/orchestra-howto", host: "store", title: "How To — Default Orchestra (AUM/AudioLayer)"))
        let howto = """
        What
        - Curate a default orchestra for AUM/AudioLayer and record a routing blueprint (reference) to FountainStore. The in‑app routing view is removed to focus on MIDI 2.0 flows; BLE default routing remains via QF_BLE_TARGET.

        Steps
        1. Seed docs (Partiture, HOWTO, starter blueprint):
           - CORPUS_ID=\(corpusId) AUM_BLE_NAME=\(bleName) FOUNTAINSTORE_DIR=.fountain/store swift run --package-path Packages/FountainApps quietframe-orchestra-seed
        2. Generate/update routing blueprint from Partiture (for reference, not consumed in‑app):
           - CORPUS_ID=\(corpusId) FOUNTAINSTORE_DIR=.fountain/store swift run --package-path Packages/FountainApps quietframe-orchestra-generate
        3. In QuietFrame Sonify:
           - Set BLE target via env `QF_BLE_TARGET="\(bleName)"` to route instrument output to iPad by default.
        4. In AUM:
           - Create an AudioLayer instance; ensure it listens to the desired MIDI channels; load samples per part as needed.

        Files / Store
        - Partiture: docs:quietframe:orchestra-default:doc (YAML)
        - CC mapping: docs:quietframe:cc-mapping:doc (JSON)
        - Routes (reference): prompt:quietframe-routing:routes (JSON)

        Roles (concise)
        - Composer/Director: author Partiture YAML
        - Instrument Tech: CC Mapping + test pad
        - Operator: Transports health (BLE/RTP) + logs
        """
        _ = try? await client.addSegment(.init(corpusId: corpusId, segmentId: "\(howtoPage):doc", pageId: howtoPage, kind: "doc", text: howto))

        // Optional: seed a ready-to-load routing blueprint (prompt:quietframe-routing:routes)
        var destinations: [String] = ["BLE: \(bleName)"]
        destinations.append(contentsOf: rtpTargets.map { "RTP: \($0)" })
        let routes: [[String: Any]] = [
            // Map each channel to the BLE target, group 0, filters on, channelMask single
            // Represented using our routing blueprint schema
        ]
        var arr: [[String: Any]] = []
        for ch in 1...16 {
            let route: [String: Any] = [
                "row": 0,
                "col": 0,
                "group": 0,
                "channelMask": [ch],
                "filters": ["cv2": 1, "m1": 1, "pe": 1, "utility": 1]
            ]
            arr.append(route)
        }
        let blueprint: [String: Any] = [
            "sources": ["QuietFrame (local)"],
            "destinations": destinations,
            "routes": arr
        ]
        if let data = try? JSONSerialization.data(withJSONObject: blueprint, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) {
            _ = try? await client.addSegment(.init(corpusId: corpusId, segmentId: "prompt:quietframe-routing:routes", pageId: "prompt:quietframe-routing", kind: "facts", text: text))
        }
        print("Seeded orchestra mapping + routes → corpus=\(corpusId)")
    }
}
