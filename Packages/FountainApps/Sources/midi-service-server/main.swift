import Foundation
import FountainRuntime
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
            return HTTPResponse(status: 404)
        }

        let transport = NIOOpenAPIServerTransport(fallback: fallback)
        do {
            try MIDIServiceServer.register(on: transport)
        } catch {
            FileHandle.standardError.write(Data("[midi-service] register failed: \(error)\n".utf8))
        }
        let server = NIOHTTPServer(kernel: transport.asKernel())

        Task {
            do {
                var bound: Int
                do { bound = try await server.start(port: port) } catch { bound = try await server.start(port: 0) }
                print("midi-service listening on :\(bound)")
            } catch {
                FileHandle.standardError.write(Data("[midi-service] failed to start: \(error)\n".utf8))
            }
        }
        dispatchMain()
    }
}

