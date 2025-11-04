import Foundation
import AppKit
import FountainStoreClient
import LauncherSignature

@main
struct PBVRTQuietFrameProof {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }
        let corpusId = env["CORPUS_ID"] ?? "pb-vrt-project"
        let segId = env["SEGMENT_ID"] ?? "prompt:pbvrt-quietframe:doc"
        let outDir = env["PROOF_DIR"] ?? ".fountain/artifacts/pb-vrt-project/proofs"

        let store: FountainStoreClient = {
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                let url = dir.hasPrefix("~") ? URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true) : URL(fileURLWithPath: dir, isDirectory: true)
                if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
            }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()

        guard let data = try? await store.getDoc(corpusId: corpusId, collection: "segments", id: segId), let text = String(data: data, encoding: .utf8) else {
            FileHandle.standardError.write(Data("[proof] segment not found or not text: corpus=\(corpusId) segment=\(segId)\n".utf8))
            return
        }

        // A4 at 144 DPI (~2x 72pt) for crisper type
        let dpi: CGFloat = 144
        let a4pt = CGSize(width: 595, height: 842)
        let size = CGSize(width: a4pt.width * dpi/72, height: a4pt.height * dpi/72)
        let margin: CGFloat = 36 * dpi/72
        let outURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(outDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill(); NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        // Border
        NSColor(calibratedWhite: 0.8, alpha: 1).setStroke(); NSBezierPath(rect: CGRect(origin: .zero, size: size)).stroke()
        // Title and body
        let title = "PB‑VRT — Quiet Frame (Golden Baseline)"
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor.black
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.userFixedPitchFont(ofSize: 11) ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor.black
        ]
        let titleRect = CGRect(x: margin, y: size.height - margin - 28, width: size.width - 2*margin, height: 24)
        (title as NSString).draw(in: titleRect, withAttributes: titleAttrs)
        let bodyRect = CGRect(x: margin, y: margin, width: size.width - 2*margin, height: size.height - 2*margin - 32)
        (text as NSString).draw(in: bodyRect, withAttributes: bodyAttrs)
        image.unlockFocus()

        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let proofPath = outURL.appendingPathComponent("quietframe-proof.tiff")
        try? rep.tiffRepresentation?.write(to: proofPath)
        print(proofPath.path)
    }
}

