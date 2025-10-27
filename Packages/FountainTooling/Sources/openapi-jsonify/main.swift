import Foundation
import Yams

@main
enum Main {
    static func readAll(_ url: URL) throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        // Simple blocking fetch for HTTP(S) URLs; rely on system URLSession
        let sem = DispatchSemaphore(value: 0)
        var out = Data()
        var err: Error?
        let task = URLSession.shared.dataTask(with: url) { data, _, e in
            if let d = data { out = d }
            err = e
            sem.signal()
        }
        task.resume()
        sem.wait()
        if let e = err { throw e }
        return out
    }

    static func run() throws {
        var specPath: String?
        let args = Array(CommandLine.arguments.dropFirst())
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "--spec", i + 1 < args.count {
                specPath = args[i + 1]
                i += 2
                continue
            }
            i += 1
        }
        guard let specPath else {
            FileHandle.standardError.write(Data("usage: openapi-jsonify --spec <path-or-url>\n".utf8))
            exit(2)
        }
        let url: URL
        if let u = URL(string: specPath), u.scheme != nil { url = u } else { url = URL(fileURLWithPath: specPath) }
        let data = try readAll(url)
        // If input is already JSON, pass it through
        if let jsonObj = try? JSONSerialization.jsonObject(with: data), JSONSerialization.isValidJSONObject(jsonObj) {
            let out = try JSONSerialization.data(withJSONObject: jsonObj)
            FileHandle.standardOutput.write(out)
            return
        }
        // Otherwise, parse YAML and dump JSON
        guard let text = String(data: data, encoding: .utf8), let obj = try Yams.load(yaml: text) else {
            throw NSError(domain: "openapi-jsonify", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read JSON or YAML from \(specPath)"])
        }
        if let dict = obj as? [String: Any], JSONSerialization.isValidJSONObject(dict) {
            let out = try JSONSerialization.data(withJSONObject: dict)
            FileHandle.standardOutput.write(out)
            return
        }
        if let arr = obj as? [Any], JSONSerialization.isValidJSONObject(arr) {
            let out = try JSONSerialization.data(withJSONObject: arr)
            FileHandle.standardOutput.write(out)
            return
        }
        throw NSError(domain: "openapi-jsonify", code: 2, userInfo: [NSLocalizedDescriptionKey: "YAML contained unsupported structures for JSON serialization"])
    }

    static func main() {
        do { try run() } catch {
            let msg = "error: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(msg.utf8))
            exit(1)
        }
    }
}

