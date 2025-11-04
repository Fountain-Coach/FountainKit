import Foundation
import CoreVideo
import CoreGraphics
import CoreML

public enum VisionAudioHelpers {
    // Creates an empty ARGB pixel buffer for simple vision model plumbing.
    public static func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferMetalCompatibilityKey: true as CFBoolean,
            kCVPixelBufferCGImageCompatibilityKey: true as CFBoolean,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true as CFBoolean
        ] as CFDictionary
        let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs, &pb)
        return status == kCVReturnSuccess ? pb : nil
    }

    // Wrap interleaved mono/stereo float samples into MLMultiArray [channels, frames].
    public static func audioSamplesToMultiArray(samples: [Float], channels: Int) throws -> MLMultiArray {
        precondition(channels == 1 || channels == 2, "Only mono/stereo supported in helper")
        let frames = samples.count / channels
        var planar = [Float](repeating: 0, count: channels * frames)
        if channels == 1 {
            planar = samples
        } else {
            for i in 0..<frames {
                planar[i] = samples[2*i]
                planar[frames + i] = samples[2*i + 1]
            }
        }
        return try CoreMLInterop.makeMultiArray(planar, shape: [channels, frames])
    }

    /// Create an RGBA CVPixelBuffer and draw the CGImage scaled to fit.
    public static func pixelBuffer(from image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        guard let pb = makePixelBuffer(width: width, height: height) else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        if let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pb),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) {
            ctx.interpolationQuality = .high
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let iw = image.width, ih = image.height
            let ar = CGFloat(iw) / CGFloat(ih)
            let tw = CGFloat(width), th = CGFloat(height)
            var drawRect = CGRect(x: 0, y: 0, width: tw, height: th)
            if ar > tw/th {
                let h = tw / ar
                drawRect = CGRect(x: 0, y: (th - h)/2, width: tw, height: h)
            } else {
                let w = th * ar
                drawRect = CGRect(x: (tw - w)/2, y: 0, width: w, height: th)
            }
            ctx.draw(image, in: drawRect)
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        return pb
    }
}
