import Foundation
import AppKit

@main
struct ImgRMSE {
    static func usage() {
        fputs("Usage: img-rmse [-t threshold] baseline.tiff actual.tiff [--heatmap out.tiff]\n", stderr)
    }

    static func loadBitmap(_ url: URL) -> NSBitmapImageRep? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return NSBitmapImageRep(data: data)
    }

    static func rmseAndHeatmap(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> (Double, NSImage?) {
        let w = min(a.pixelsWide, b.pixelsWide)
        let h = min(a.pixelsHigh, b.pixelsHigh)
        let bytesPerPixel = 4
        var sum: Double = 0
        var count: Double = 0
        var heat = [UInt8](repeating: 0, count: w*h*bytesPerPixel)
        for y in 0..<h {
            for x in 0..<w {
                var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
                var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
                a.colorAt(x: x, y: y)?.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
                b.colorAt(x: x, y: y)?.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
                let dr = Double(ar - br), dg = Double(ag - bg), db = Double(ab - bb)
                sum += dr*dr + dg*dg + db*db
                count += 3
                let mag = min(1.0, sqrt(dr*dr + dg*dg + db*db))
                let r = UInt8(min(255.0, mag*255.0))
                let i = (y*w + x)*bytesPerPixel
                heat[i+0] = r; heat[i+1] = 0; heat[i+2] = 0; heat[i+3] = 255
            }
        }
        let rmse = sqrt(sum / max(1, count)) * 255.0
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w*bytesPerPixel, bitsPerPixel: bytesPerPixel*8)!
        heat.withUnsafeBytes { raw in
            rep.bitmapData?.update(from: raw.bindMemory(to: UInt8.self).baseAddress!, count: w*h*bytesPerPixel)
        }
        let img = NSImage(size: NSSize(width: w, height: h)); img.addRepresentation(rep)
        return (rmse, img)
    }

    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        var threshold: Double = 3.0
        var heatmapOut: URL? = nil
        while let a = args.first, a.hasPrefix("-") {
            args.removeFirst()
            switch a {
            case "-h", "--help":
                usage(); exit(2)
            case "-t", "--threshold":
                guard let v = args.first, let d = Double(v) else { usage(); exit(2) }
                threshold = d; args.removeFirst()
            case "--heatmap":
                guard let v = args.first else { usage(); exit(2) }
                heatmapOut = URL(fileURLWithPath: v); args.removeFirst()
            default:
                usage(); exit(2)
            }
        }
        guard args.count >= 2 else { usage(); exit(2) }
        let baseURL = URL(fileURLWithPath: args[0])
        let actURL = URL(fileURLWithPath: args[1])
        guard let a = loadBitmap(baseURL) else { fputs("error: cannot load baseline \(baseURL.path)\n", stderr); exit(3) }
        guard let b = loadBitmap(actURL) else { fputs("error: cannot load actual \(actURL.path)\n", stderr); exit(3) }
        let (rmse, heat) = rmseAndHeatmap(a, b)
        print(String(format: "rmse=%.3f", rmse))
        if rmse > threshold, let heat, let data = heat.tiffRepresentation, let out = heatmapOut {
            try? data.write(to: out)
            fputs("wrote heatmap: \(out.path)\n", stderr)
        }
        if rmse > threshold { exit(1) }
        exit(0)
    }
}

