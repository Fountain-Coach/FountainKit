import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct PBVRTQuietFrameDump {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }
        let corpusId = env["CORPUS_ID"] ?? "pb-vrt-project"
        let segId = env["SEGMENT_ID"] ?? "prompt:pbvrt-quietframe:doc"
        let store: FountainStoreClient = {
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                let url = dir.hasPrefix("~") ? URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true) : URL(fileURLWithPath: dir, isDirectory: true)
                if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
            }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()
        if let data = try? await store.getDoc(corpusId: corpusId, collection: "segments", id: segId) {
            if let s = String(data: data, encoding: .utf8) { print(s) }
            else { FileHandle.standardError.write(Data("[dump] segment exists but is not UTF‑8 text\n".utf8)) }
        } else {
            FileHandle.standardError.write(Data("[dump] segment not found: corpus=\(corpusId) segment=\(segId)\n".utf8))
        }
    }
}

