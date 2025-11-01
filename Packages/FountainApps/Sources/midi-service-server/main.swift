import Foundation
import FountainRuntime
import MIDIService
import MIDIService

@main
struct Main {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        let port = Int(env["MIDI_SERVICE_PORT"] ?? env["PORT"] ?? "7180") ?? 7180

        // Serve the spec at /openapi.yaml as a fallback route (developer aid)
        let fallback = HTTPKernel { req in
            if req.path == "/openapi.yaml" {
                let url = URL(fileURLWithPath: "Packages/FountainServiceKit-MIDI/Sources/MIDIService/openapi.yaml")
                if let data = try? Data(contentsOf: url) {
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
                }
            }
            if req.path == "/ump/tail" || req.path == "/ump/events" && req.method.uppercased() == "GET" {
                let items = await MIDIServiceRuntime.shared.tail(limit: 256)
                let payload = try? JSONEncoder().encode(["events": items])
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: payload ?? Data("{}".utf8))
            }
            if req.path == "/ump/flush" || req.path == "/ump/events" && req.method.uppercased() == "POST" {
                await MIDIServiceRuntime.shared.flush()
                return HTTPResponse(status: 204)
            }
            if req.path == "/headless/list" {
                let names = await MIDIServiceRuntime.shared.listHeadless()
                let payload = try? JSONSerialization.data(withJSONObject: ["names": names])
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: payload ?? Data("{}".utf8))
            }
            if req.path == "/headless/register" && req.method.uppercased() == "POST" {
                let body = req.body
                guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let name = obj["displayName"] as? String else {
                    return HTTPResponse(status: 400)
                }
                await MIDIServiceRuntime.shared.registerHeadless(displayName: name)
                return HTTPResponse(status: 201)
            }
            if req.path == "/headless/unregister" && req.method.uppercased() == "POST" {
                let body = req.body
                guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let name = obj["displayName"] as? String else {
                    return HTTPResponse(status: 400)
                }
                await MIDIServiceRuntime.shared.unregisterHeadless(displayName: name)
                return HTTPResponse(status: 204)
            }
            return HTTPResponse(status: 404)
        }

        let transport = NIOOpenAPIServerTransport(fallback: fallback)
        do {
            try MIDIServiceServer.register(on: transport)
        } catch {
            FileHandle.standardError.write(Data("[midi-service] register failed: \(error)\n".utf8))
        }
        let server = NIOHTTPServer(kernel: transport.asKernel())

        // Ensure listener to record incoming UMP from all sources
        Task {
            await MIDIServiceRuntime.shared.ensureListener()
            await MIDIServiceRuntime.shared.registerHeadlessCanvas()
            // Register Fountain Editor headless instrument for web/app MRTS
            await MIDIServiceRuntime.shared.registerHeadlessEditor()
            // Register Corpus Instrument headless
            await MIDIServiceRuntime.shared.registerHeadlessCorpus()
            // Register Flow instrument headless
            await MIDIServiceRuntime.shared.registerHeadlessFlow()
        }

        Task {
            do {
                var bound: Int
                do { bound = try await server.start(port: port) } catch { bound = try await server.start(port: 0) }
                print("midi-service listening on :\(bound)")
            } catch {
                FileHandle.standardError.write(Data("[midi-service] failed to start: \(error)\n".utf8))
            }
        }
        if let dir = ProcessInfo.processInfo.environment["MIDI_UMP_LOG_DIR"], !dir.isEmpty {
            Task { await MIDIServiceRuntime.shared.enableUMPLog(at: dir) }
        } else {
            // default to repo-local .fountain/corpus/ump
            let cwd = FileManager.default.currentDirectoryPath
            let dir = (cwd as NSString).appendingPathComponent(".fountain/corpus/ump")
            Task { await MIDIServiceRuntime.shared.enableUMPLog(at: dir) }
        }
        dispatchMain()
    }
}
