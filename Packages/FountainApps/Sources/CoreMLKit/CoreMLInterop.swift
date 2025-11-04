import Foundation
import CoreML

public enum CoreMLInterop {
    public struct LoadedModel {
        public let model: MLModel
        public let url: URL
    }

    // Loads a .mlmodel or compiled .mlmodelc. Compiles on the fly when needed.
    public static func loadModel(at path: String, computeUnits: MLComputeUnits = .all) throws -> LoadedModel {
        let url = URL(fileURLWithPath: path)
        let compiledURL: URL
        if url.pathExtension == "mlmodel" {
            compiledURL = try MLModel.compileModel(at: url)
        } else {
            compiledURL = url
        }
        let cfg = MLModelConfiguration()
        cfg.computeUnits = computeUnits
        let model = try MLModel(contentsOf: compiledURL, configuration: cfg)
        return LoadedModel(model: model, url: compiledURL)
    }

    // Convenience construction of MLMultiArray from [Float] with a given shape.
    public static func makeMultiArray(_ values: [Float], shape: [Int]) throws -> MLMultiArray {
        let mlshape = shape.map { NSNumber(value: $0) }
        let arr = try MLMultiArray(shape: mlshape, dataType: .float32)
        let count = values.count
        arr.dataPointer.assumingMemoryBound(to: Float.self).update(from: values, count: count)
        return arr
    }

    public static func toArray(_ arr: MLMultiArray) -> [Float] {
        let cnt = arr.count
        let ptr = arr.dataPointer.assumingMemoryBound(to: Float.self)
        return Array(UnsafeBufferPointer(start: ptr, count: cnt))
    }

    // Runs prediction on a model with a dictionary of MLMultiArray inputs. Returns MLMultiArray outputs.
    public static func predict(model: MLModel, inputs: [String: MLMultiArray]) throws -> [String: MLMultiArray] {
        let provider = try MLDictionaryFeatureProvider(dictionary: inputs.mapValues { MLFeatureValue(multiArray: $0) })
        let out = try model.prediction(from: provider)
        var dict: [String: MLMultiArray] = [:]
        for name in out.featureNames {
            if let arr = out.featureValue(for: name)?.multiArrayValue { dict[name] = arr }
        }
        return dict
    }

    // Generic variant: accept/return MLFeatureValue so callers may pass images or scalars.
    public static func predictValues(model: MLModel, inputs: [String: MLFeatureValue]) throws -> [String: MLFeatureValue] {
        let provider = try MLDictionaryFeatureProvider(dictionary: inputs)
        let out = try model.prediction(from: provider)
        var dict: [String: MLFeatureValue] = [:]
        for name in out.featureNames {
            if let v = out.featureValue(for: name) { dict[name] = v }
        }
        return dict
    }
}
