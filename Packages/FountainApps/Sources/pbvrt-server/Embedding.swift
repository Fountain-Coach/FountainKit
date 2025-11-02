import Foundation
import Vision

enum PBVRTEmbeddingBackend: String {
    case featurePrint
}

public enum PBVRTEngineError: Error { case observationFailed }

public enum PBVRTEngine {
    public static func featureprintDistance(baseline: Data, candidate: Data) throws -> Double {
        let baseObs = try observation(for: baseline)
        let candObs = try observation(for: candidate)
        var dist: Float = 0
        try baseObs.computeDistance(&dist, to: candObs)
        return Double(dist)
    }

    private static func observation(for data: Data) throws -> VNFeaturePrintObservation {
        let req = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(data: data, options: [:])
        try handler.perform([req])
        guard let obs = req.results?.first as? VNFeaturePrintObservation else {
            throw PBVRTEngineError.observationFailed
        }
        return obs
    }
}
