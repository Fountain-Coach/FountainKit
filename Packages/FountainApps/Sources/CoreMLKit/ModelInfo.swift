import Foundation
import CoreML

public struct ModelSummary: Sendable {
    public struct Feature: Sendable {
        public let name: String
        public let type: MLFeatureType
        public let shape: [Int]
        public init(name: String, type: MLFeatureType, shape: [Int]) {
            self.name = name
            self.type = type
            self.shape = shape
        }
    }
    public let inputs: [Feature]
    public let outputs: [Feature]
}

public enum ModelInfo {
    public static func summarize(_ model: MLModel) -> ModelSummary {
        let md = model.modelDescription
        let ins = md.inputDescriptionsByName.map { (k, v) in
            ModelSummary.Feature(name: k, type: v.type, shape: v.multiArrayConstraint?.shape.map { $0.intValue } ?? [])
        }.sorted { $0.name < $1.name }
        let outs = md.outputDescriptionsByName.map { (k, v) in
            ModelSummary.Feature(name: k, type: v.type, shape: v.multiArrayConstraint?.shape.map { $0.intValue } ?? [])
        }.sorted { $0.name < $1.name }
        return ModelSummary(inputs: ins, outputs: outs)
    }
}

