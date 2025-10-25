import Foundation
import ArgumentParser

@main
struct CoreMLFetch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Fetch sample Core ML models or print conversion notes",
        subcommands: [SqueezeNet.self, YamNet.self, URLFetch.self, Notes.self],
        defaultSubcommand: SqueezeNet.self
    )

    struct SqueezeNet: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Download Apple SqueezeNet.mlmodel to Public/Models/")
        @Option(name: .long, help: "Destination directory") var outDir: String = "Public/Models"
        func run() throws {
            let url = URL(string: "https://docs-assets.developer.apple.com/coreml/models/SqueezeNet.mlmodel")!
            try fetch(url: url, fileName: "SqueezeNet.mlmodel", outDir: outDir)
        }
    }

    struct URLFetch: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Download a model by URL to Public/Models (or custom dir)")
        @Argument(help: "URL to .mlmodel or .mlmodelc") var url: String
        @Option(name: .long, help: "Destination directory") var outDir: String = "Public/Models"
        @Option(name: .long, help: "Override file name (optional)") var fileName: String?
        func run() throws { try fetch(url: URL(string: url)!, fileName: fileName, outDir: outDir) }
    }

    struct YamNet: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Download YAMNet TFLite + class map; optional Core ML conversion")
        @Option(name: .long, help: "Destination directory") var outDir: String = "Public/Models"
        @Flag(name: .long, help: "Convert to Core ML using Scripts/apps/coreml-convert.sh") var convert: Bool = false
        func run() throws {
            let src = URL(string: "https://storage.googleapis.com/audioset/yamnet/yamnet.tflite")!
            let labels = URL(string: "https://storage.googleapis.com/audioset/yamnet/yamnet_class_map.csv")!
            try fetch(url: src, fileName: "YAMNet.tflite", outDir: outDir)
            try fetch(url: labels, fileName: "yamnet_class_map.csv", outDir: outDir)
            if convert {
                let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                let script = root.appendingPathComponent("Scripts/apps/coreml-convert.sh").path
                let tfl = URL(fileURLWithPath: outDir).appendingPathComponent("YAMNet.tflite").path
                let out = URL(fileURLWithPath: outDir).appendingPathComponent("YAMNet.mlmodel").path
                print("[convert] invoking: \(script) tflite --tflite \(tfl) --frame 1024 --out \(out)")
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = [script, "tflite", "--tflite", tfl, "--frame", "1024", "--out", out]
                try p.run(); p.waitUntilExit()
                if p.terminationStatus != 0 { throw NSError(domain: "coreml-fetch", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Conversion script failed"]) }
            } else {
                print("[hint] To convert to Core ML: Scripts/apps/coreml-convert.sh tflite --tflite \(outDir)/YAMNet.tflite --frame 15600 --out \(outDir)/YAMNet.mlmodel")
            }
        }
    }

    struct Notes: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print conversion steps for CREPE/BasicPitch and tips")
        func run() throws {
            let text = """
            === Conversion Notes (CoreMLTools) ===

            CREPE (pitch tracking):
              - Source: https://github.com/marl/crepe (TensorFlow)
              - Steps (Python, coremltools):
                1) pip install coremltools tensorflow==2.15 numpy
                2) Export the TF graph or SavedModel for the desired variant (tiny/small).
                3) Convert: coremltools.convert(saved_model_dir, inputs=[ct.TensorType(shape=(1, N), dtype=float32)])
                4) Ensure output is 360-bin distribution (softmax) to use CREPE decode in ml-audio2midi.
                5) Save as CREPE.mlmodel and test: COREML_MODEL=CREPE.mlmodel coreml-demo

            BasicPitch (poly transcription):
              - Source: https://github.com/spotify/basic-pitch
              - Steps (Python):
                1) pip install coremltools basic-pitch tensorflow==2.15 numpy librosa
                2) Export the Keras/TFLite model to SavedModel or load directly.
                3) Convert with coremltools; pick an I/O signature that yields per-frame pitch probabilities
                   shape ≈ [frames, pitches] (88 or 128). ml-basicpitch2midi reads last frame and thresholds.
                4) Save as BasicPitch.mlmodel and test with ml-basicpitch2midi --model BasicPitch.mlmodel.

            Tips:
              - Do not commit .mlmodelc; compile on demand (CoreMLKit handles it).
              - Keep models under Public/Models (first-party) or External/Models (third-party).
              - Verify on this machine with: swift run --package-path Packages/FountainApps coreml-demo
              - Shell helper in this repo to automate conversions (sets up .coremlvenv):
                Scripts/apps/coreml-convert.sh --help
            """
            print(text)
        }
    }
}

// MARK: - Utilities
private func fetch(url: URL, fileName: String?, outDir: String) throws {
    let fm = FileManager.default
    if !fm.fileExists(atPath: outDir) {
        try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    }
    let dest = URL(fileURLWithPath: outDir).appendingPathComponent(fileName ?? url.lastPathComponent)
    print("[fetch] GET \(url.absoluteString) → \(dest.path)")
    let sem = DispatchSemaphore(value: 0)
    var err: Error?
    var dataOut: Data?
    let task = URLSession.shared.dataTask(with: url) { data, resp, e in
        if let e = e { err = e }
        else if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            err = NSError(domain: "coreml-fetch", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        } else { dataOut = data }
        sem.signal()
    }
    task.resume()
    sem.wait()
    if let e = err { throw e }
    guard let data = dataOut else { throw NSError(domain: "coreml-fetch", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]) }
    try data.write(to: dest, options: .atomic)
    print("[fetch] wrote \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
}
