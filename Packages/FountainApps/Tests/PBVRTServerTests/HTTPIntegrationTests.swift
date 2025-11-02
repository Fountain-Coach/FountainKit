import XCTest
@testable import pbvrt_server
import FountainRuntime
import FountainStoreClient
import Foundation
import UniformTypeIdentifiers

final class PBVRTHTTPIntegrationTests: XCTestCase {
    func makeKernelAndStore(tmp: URL, corpus: String = "pbvrt-test") async -> (HTTPKernel, FountainStoreClient) {
        let store = try! DiskFountainStoreClient(rootDirectory: tmp)
        let fc = FountainStoreClient(client: store)
        let transport = NIOOpenAPIServerTransport()
        let artifacts = tmp.appendingPathComponent("artifacts", isDirectory: true)
        try? FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        let handlers = PBVRTHandlers(store: fc, corpusId: corpus, artifactsRoot: artifacts)
        try? handlers.registerHandlers(on: transport, serverURL: URL(string: "/pb-vrt")!)
        return (transport.asKernel(), fc)
    }

    func multipart(_ parts: [(name: String, filename: String?, contentType: String?, data: Data)], boundary: String) -> (Data, String) {
        var body = Data()
        let lineBreak = "\r\n".data(using: .utf8)!
        for p in parts {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            var disp = "Content-Disposition: form-data; name=\"\(p.name)\""
            if let fn = p.filename { disp += "; filename=\"\(fn)\"" }
            body.append((disp + "\r\n").data(using: .utf8)!)
            if let ct = p.contentType { body.append(("Content-Type: \(ct)\r\n").data(using: .utf8)!) }
            body.append(lineBreak)
            body.append(p.data)
            body.append(lineBreak)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return (body, "multipart/form-data; boundary=\(boundary)")
    }

    func smallPNG(size: Int = 32, whiteSquare: Bool = false) -> Data {
        let w = size, h = size
        let cs = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = w * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * h)
        if whiteSquare {
            for y in 8..<(h-8) { for x in 8..<(w-8) {
                let idx = y*bytesPerRow + x*4
                pixels[idx+0] = 255; pixels[idx+1] = 255; pixels[idx+2] = 255; pixels[idx+3] = 255
            }}
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: cs, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return try! img.pngData()
    }

    func sineWav(sr: Int = 16000, f: Double = 440.0, dur: Double = 0.1) -> Data {
        let n = Int(Double(sr) * dur)
        var samples = [Int16](repeating: 0, count: n)
        for i in 0..<n {
            let v = sin(2*Double.pi * f * Double(i) / Double(sr))
            samples[i] = Int16(max(-1.0, min(1.0, v)) * Double(Int16.max))
        }
        var data = Data()
        let byteRate = sr * 2
        let blockAlign: UInt16 = 2
        let subchunk2Size = samples.count * MemoryLayout<Int16>.size
        let chunkSize = 36 + subchunk2Size
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(chunkSize).littleEndianData)
        data.append("WAVEfmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt32(sr).littleEndianData)
        data.append(UInt32(byteRate).littleEndianData)
        data.append(blockAlign.littleEndianData)
        data.append(UInt16(16).littleEndianData)
        data.append("data".data(using: .ascii)!)
        data.append(UInt32(subchunk2Size).littleEndianData)
        samples.withUnsafeBytes { data.append($0) }
        return data
    }

    func testSaliencyCompareHTTP() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, store) = await makeKernelAndStore(tmp: tmp)
        // multipart body
        let boundary = "XBOUNDARY"
        let (body, ctype) = multipart([
            (name: "baselinePng", filename: "b.png", contentType: "image/png", data: smallPNG()),
            (name: "candidatePng", filename: "c.png", contentType: "image/png", data: smallPNG())
        ], boundary: boundary)
        let req = HTTPRequest(method: "POST", path: "/pb-vrt/probes/saliency/compare", headers: ["Content-Type": ctype], body: body)
        let resp = try await kernel.handle(req)
        XCTAssertEqual(resp.status, 200)
        // confirm store wrote ad-hoc saliency summary
        let qr = try await store.query(corpusId: "pbvrt-test", collection: "segments", query: Query(filters: ["kind": "pbvrt.vision.saliency"]))
        XCTAssertGreaterThanOrEqual(qr.total, 1)
    }

    func testSpectrogramCompareHTTP() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, store) = await makeKernelAndStore(tmp: tmp)
        let b = sineWav()
        let c = sineWav()
        let boundary = "XBOUNDARY2"
        let (body, ctype) = multipart([
            (name: "baselineWav", filename: "b.wav", contentType: "audio/wav", data: b),
            (name: "candidateWav", filename: "c.wav", contentType: "audio/wav", data: c)
        ], boundary: boundary)
        let req = HTTPRequest(method: "POST", path: "/pb-vrt/probes/audio/spectrogram/compare", headers: ["Content-Type": ctype], body: body)
        let resp = try await kernel.handle(req)
        XCTAssertEqual(resp.status, 200)
        let qr = try await store.query(corpusId: "pbvrt-test", collection: "segments", query: Query(filters: ["kind": "pbvrt.audio.spectrogram"]))
        XCTAssertGreaterThanOrEqual(qr.total, 1)
    }

    func testCompareCandidateWritesBaselineSegment() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, store) = await makeKernelAndStore(tmp: tmp)
        let corpus = "pbvrt-test"
        let baselineId = UUID().uuidString
        // Seed minimal baseline page + segment and artifact folder with baseline.png
        let pageId = "pbvrt:baseline:\(baselineId)"
        _ = try? await store.addPage(Page(corpusId: corpus, pageId: pageId, url: "store://pbvrt/baseline/\(baselineId)", host: "store", title: "PBVRT Baseline \(baselineId)"))
        let artifactsRoot = tmp.appendingPathComponent("artifacts", isDirectory: true).appendingPathComponent(baselineId, isDirectory: true)
        try? FileManager.default.createDirectory(at: artifactsRoot, withIntermediateDirectories: true)
        try smallPNG().write(to: artifactsRoot.appendingPathComponent("baseline.png"))
        let baselineMeta: [String: Any] = ["baselineId": baselineId, "artifacts": ["baselinePng": artifactsRoot.appendingPathComponent("baseline.png").path]]
        if let data = try? JSONSerialization.data(withJSONObject: baselineMeta, options: [.sortedKeys]), let s = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpus, segmentId: "\(pageId):pbvrt.baseline", pageId: pageId, kind: "pbvrt.baseline", text: s))
        }
        // call /compare
        let boundary = "BOUND3"
        let (body, ctype) = multipart([
            (name: "baselineId", filename: nil, contentType: nil, data: Data(baselineId.utf8)),
            (name: "candidatePng", filename: "cand.png", contentType: "image/png", data: smallPNG())
        ], boundary: boundary)
        let req = HTTPRequest(method: "POST", path: "/pb-vrt/compare", headers: ["Content-Type": ctype], body: body)
        let resp = try await kernel.handle(req)
        XCTAssertEqual(resp.status, 200)
        // verify pbvrt.compare segment exists
        let segId = "\(pageId):pbvrt.compare"
        let got = try await store.getDoc(corpusId: corpus, collection: "segments", id: segId)
        XCTAssertNotNil(got)
    }
}

private extension UInt16 { var littleEndianData: Data { withUnsafeBytes(of: self.littleEndian, { Data($0) }) } }
private extension UInt32 { var littleEndianData: Data { withUnsafeBytes(of: self.littleEndian, { Data($0) }) } }

private extension CGImage {
    func pngData() throws -> Data { try autoreleasepool { let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".png"); try self.writePNG(to: url); return try Data(contentsOf: url) } }
    func writePNG(to url: URL) throws {
        guard let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw NSError(domain: "cg", code: -1) }
        CGImageDestinationAddImage(dst, self, nil)
        guard CGImageDestinationFinalize(dst) else { throw NSError(domain: "cg", code: -2) }
    }
}
