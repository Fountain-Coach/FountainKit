import AppKit

enum ReplayDiffUtil {
    struct DiffResult { let mse: Double; let changedPixels: Int }
    static func diff(_ a: NSImage, _ b: NSImage) -> DiffResult {
        guard let ra = a.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let rb = b.cgImage(forProposedRect: nil, context: nil, hints: nil),
              ra.width == rb.width, ra.height == rb.height else {
            return .init(mse: Double.infinity, changedPixels: Int.max)
        }
        let w = ra.width, h = ra.height
        let bytesPerRow = w * 4
        var bufA = [UInt8](repeating: 0, count: Int(bytesPerRow * h))
        var bufB = [UInt8](repeating: 0, count: Int(bytesPerRow * h))
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctxA = CGContext(data: &bufA, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let ctxB = CGContext(data: &bufB, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return .init(mse: Double.infinity, changedPixels: Int.max)
        }
        ctxA.draw(ra, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctxB.draw(rb, in: CGRect(x: 0, y: 0, width: w, height: h))
        var se: Double = 0
        var changes = 0
        for i in 0..<(Int(bytesPerRow * h)) {
            let d = Int(bufA[i]) - Int(bufB[i])
            if d != 0 { changes += 1 }
            se += Double(d*d)
        }
        let mse = se / Double(bytesPerRow * h)
        return .init(mse: mse, changedPixels: changes)
    }
    static func snapshot(_ view: NSView) -> NSImage? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let img = NSImage(size: view.bounds.size)
        img.addRepresentation(rep)
        return img
    }
    static func save(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation else { return }
        try? tiff.write(to: url)
    }
}

