import Foundation
import TeatroRenderAPI

enum AdapterError: Error { case fileMissing, invalidEncoding }

@MainActor
struct AdapterFountainToTeatro {
    static func render(path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { throw AdapterError.fileMissing }
        let textData = try Data(contentsOf: url)
        guard let text = String(data: textData, encoding: .utf8) else { throw AdapterError.invalidEncoding }
        let result = try TeatroRenderer.renderScript(SimpleScriptInput(fountainText: text))
        guard let svgData = result.svg, let svg = String(data: svgData, encoding: .utf8) else {
            return "<html><body><pre>No SVG produced</pre></body></html>"
        }
        return svg
    }
}
