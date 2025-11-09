import XCTest
import AppKit

@MainActor
enum SnapshotUtils {
    struct DiffResult { let rmse: Double; let heatmap: NSImage }

    static func renderImage(of view: NSView, size: CGSize) -> NSImage {
        view.setFrameSize(size)
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        let img = NSImage(size: size)
        img.addRepresentation(rep)
        return img
    }

    static func writePNG(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "snapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "png encode failed"])
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
    }

    static func loadPNG(_ url: URL) -> NSImage? {
        guard let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else { return nil }
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }

    static func diffRMSE(_ a: NSImage, _ b: NSImage) -> DiffResult? {
        guard let ra = bitmap(a), let rb = bitmap(b), ra.pixelsWide == rb.pixelsWide, ra.pixelsHigh == rb.pixelsHigh else { return nil }
        let w = ra.pixelsWide, h = ra.pixelsHigh
        var sum: Double = 0
        let heat = NSImage(size: NSSize(width: w, height: h))
        heat.lockFocus()
        NSColor.black.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: w, height: h)).fill()
        for y in 0..<h {
            for x in 0..<w {
                let ca = color(ra, x, y)
                let cb = color(rb, x, y)
                let dr = Double(ca.redComponent - cb.redComponent)
                let dg = Double(ca.greenComponent - cb.greenComponent)
                let db = Double(ca.blueComponent - cb.blueComponent)
                let e = (dr*dr + dg*dg + db*db)/3.0
                sum += e
                if e > 0.0001 {
                    NSColor(calibratedRed: CGFloat(min(1, e*20)), green: 0, blue: 0, alpha: 1).setFill()
                    NSBezierPath(rect: NSRect(x: x, y: h-1-y, width: 1, height: 1)).fill()
                }
            }
        }
        heat.unlockFocus()
        let rmse = sqrt(sum / Double(w*h))
        return DiffResult(rmse: rmse, heatmap: heat)
    }

    private static func bitmap(_ img: NSImage) -> NSBitmapImageRep? {
        guard let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t) else { return nil }
        return rep.converting(to: .sRGB, renderingIntent: .default)
    }

    private static func color(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> NSColor {
        rep.colorAt(x: x, y: y) ?? .black
    }
}

