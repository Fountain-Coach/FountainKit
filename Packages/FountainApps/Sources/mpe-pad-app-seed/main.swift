import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct MPEPadAppSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }
        let corpusId = env["CORPUS_ID"] ?? "mpe-pad-app"
        let store = resolveStore()
        do { _ = try await store.createCorpus(corpusId, metadata: ["app": "mpe-pad-app", "kind": "teatro+instruments"]) } catch { /* ignore */ }

        // Creation prompt (authoritative GUI description)
        let pageId = "prompt:mpe-pad-app"
        let page = Page(corpusId: corpusId, pageId: pageId, url: "store://prompt/mpe-pad-app", host: "store", title: "MPE Pad App — Teatro Prompt")
        _ = try? await store.addPage(page)
        let creation = creationPrompt()
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):teatro", pageId: pageId, kind: "teatro.prompt", text: creation))

        // Facts (structured JSON: instruments, PE fields, ops, invariants)
        let facts: [String: Any] = [
            "instruments": [[
                "manufacturer": "Fountain",
                "product": "MPEPad",
                "instanceId": "mpe-pad-1",
                "displayName": "MPE Pad",
                "ci": ["protocol": "midi2", "identity": "Fountain|MPEPad|mpe-pad-1"],
                "pe": [
                    "transport.mode",               // blePeripheral | bleCentral | rtp
                    "transport.ble.filter",         // substring match
                    "transport.rtp.port",           // 1024..65535
                    "mpe.bendRange",                // semitones (2..96)
                    "mpe.zone",                     // lower|upper; default lower
                    "mpe.baseChannel",              // 2..16 (lower zone first member)
                    "ui.localAudio.enabled"         // 0|1, local preview sine
                ],
                "ops": [
                    "mpe.open", "mpe.note", "mpe.pitchbend", "mpe.polyaftertouch"
                ],
                "vendorJSON": []
            ]],
            "openapi": [
                ["opId": "mpe.open", "path": "/mpe/open", "method": "POST"],
                ["opId": "mpe.note", "path": "/mpe/note", "method": "POST"],
                ["opId": "mpe.pitchbend", "path": "/mpe/pitchbend", "method": "POST"],
                ["opId": "mpe.polyaftertouch", "path": "/mpe/polyaftertouch", "method": "POST"]
            ],
            "robot": [
                "subset": ["MPEPadMappingTests", "MPEPadBLEConnectivityTests"],
                "invariants": [
                    "drag.x maps to continuous pitch bend in ±bendRange",
                    "drag.y maps to velocity [20..127] with monotonic increase",
                    "polyaftertouch mirrors current pressure (or velocity proxy)",
                    "center x produces pitch bend ~8192",
                    "mpe.open sets bend range via RPN 0,0 across member channels"
                ]
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted]), let json = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: json))
        }

        // Optional MRTS prompt (separate page, same corpus)
        let mrtsp = mrtsprompt()
        let mrtsPageId = "prompt:mpe-pad-app-mrts"
        let mrtsPage = Page(corpusId: corpusId, pageId: mrtsPageId, url: "store://prompt/mpe-pad-app-mrts", host: "store", title: "MPE Pad App — MRTS")
        _ = try? await store.addPage(mrtsPage)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(mrtsPageId):teatro", pageId: mrtsPageId, kind: "teatro.prompt", text: mrtsp))

        print("Seeded MPE Pad prompts → corpus=\(corpusId) pages=[\(pageId), \(mrtsPageId)]")
    }

    static func resolveStore() -> FountainStoreClient {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
            let url: URL
            if dir.hasPrefix("~") {
                url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
            } else { url = URL(fileURLWithPath: dir, isDirectory: true) }
            if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) {
            return FountainStoreClient(client: disk)
        }
        return FountainStoreClient(client: EmbeddedFountainStoreClient())
    }

    static func creationPrompt() -> String {
        return """
        Scene: MPE Pad App — Minimal Instrument for BLE/RTP MPE
        Text:
        - Window: macOS titlebar, 960×600 pt. Single vertical stack: control row + pad.
        - Control Row (top):
          • Transport toggle: BLE Peripheral | BLE Central | RTP (segmented). Default: BLE Peripheral.
          • BLE filter (text field) shown for Central; default "AUM".
          • RTP port (stepper) shown for RTP; default 5869.
          • Bend range (stepper) ±[2..96], default 48.
          • Local Audio (toggle): preview sine for quick sanity.
          • Open/Close (toggle): opens transport and advertises/starts session, applies bend range across member channels (RPN 0,0).
        - Pad (center): rounded rect; drag to play.
          • X axis → continuous pitch bend; center ≈ 8192; linear mapping across ±bendRange semitones.
          • Y axis → velocity in [20..127]; higher = louder. Changes note when crossing semitone boundaries (24‑semitone span).
          • While dragging: sends `mpe.note` (on first), `mpe.pitchbend` (continuous), `mpe.polyaftertouch` (pressure proxy from Y).
          • On end: sends pitchbend reset (8192) + noteOff.
        - Persist minimal state (bend range, last transport mode) via FountainStore for the app corpus.

        Invariants:
        - Center X produces pitchbend ~8192 (tolerance ≤ ±1 LSB).
        - Mapping is monotonic; no jitter when idle.
        - Bend range applied to all MPE member channels upon open.

        Property Exchange (future host integration):
        - `transport.mode` (enum: blePeripheral|bleCentral|rtp)
        - `transport.ble.filter` (string)
        - `transport.rtp.port` (int 1024..65535)
        - `mpe.bendRange` (int 2..96)
        - `mpe.zone` (enum lower|upper), `mpe.baseChannel` (int 2..16)
        - `ui.localAudio.enabled` (0|1)
        """
    }

    static func mrtsprompt() -> String {
        return """
        Scene: MPE Pad App — MRTS (Mapping + Transport)
        Text:
        - Objective: validate pad mapping and transport bring‑up.
        - Steps:
          • Set `mpe.bendRange=48`; `transport.mode=rtp`; `transport.rtp.port=5869`; Open.
          • Drag across center X±10%: assert pitchbend ≈ 8192 ± ~1638.
          • Drag to left edge: assert near minimum pitchbend; to right edge: near max; monotonic sequence.
          • Vertical sweep: assert velocity increases monotonically; polyAT mirrors.
          • Release: assert pitchbend reset to ~8192; noteOff sent.
          • Switch to BLE Peripheral; Open; verify advertisement visible (observable via BLE Central scanner).
        Evidence:
        - UMP recorder outputs `.fountain/corpus/ump/*.ndjson` with note/pitchbend/aftertouch sequences.
        - Snapshots (optional) record control row visibility changes by mode.
        """
    }
}

