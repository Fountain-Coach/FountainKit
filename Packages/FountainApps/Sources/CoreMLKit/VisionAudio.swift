import Foundation
import CoreVideo
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
}

