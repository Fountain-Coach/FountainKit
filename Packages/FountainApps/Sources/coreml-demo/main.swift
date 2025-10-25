import Foundation
import CoreML
import CoreMLKit

@main
struct CoreMLDemo {
    static func main() {
        guard let modelPath = ProcessInfo.processInfo.environment["COREML_MODEL"] else {
            print("[coreml-demo] Set COREML_MODEL to a .mlmodel or compiled .mlmodelc path. Example:\n  COREML_MODEL=/path/to/Model.mlmodel swift run --package-path Packages/FountainApps coreml-demo")
            return
        }
        do {
            let loaded = try CoreMLInterop.loadModel(at: modelPath)
            let md = loaded.model.modelDescription
            print("[coreml-demo] Loaded model: \(loaded.url.lastPathComponent)")
            print("Inputs: \(md.inputDescriptionsByName.keys.joined(separator: ", "))")
            print("Outputs: \(md.outputDescriptionsByName.keys.joined(separator: ", "))")

            // Build a simple input provider with random data for the first MultiArray input
            guard let first = md.inputDescriptionsByName.first?.value else { print("No inputs found"); return }
            guard first.type == .multiArray, let maType = first.multiArrayConstraint else { print("First input is not MLMultiArray; provide a custom feeder"); return }
            let shape = maType.shape.map { $0.intValue }
            let count = shape.reduce(1, *)
            let data = (0..<count).map { _ in Float.random(in: -1...1) }
            let arr = try CoreMLInterop.makeMultiArray(data, shape: shape)
            let inputName = first.name
            let t0 = CFAbsoluteTimeGetCurrent()
            let out = try CoreMLInterop.predict(model: loaded.model, inputs: [inputName: arr])
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            print(String(format: "[coreml-demo] predict: %.2f ms", ms))
            for (k, v) in out { print("- \(k): shape=\(v.shape)") }
        } catch {
            fputs("[coreml-demo] error: \(error)\n", stderr)
        }
    }
}
