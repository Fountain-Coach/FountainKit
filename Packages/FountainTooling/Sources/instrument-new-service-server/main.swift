import Foundation
import FountainRuntime
import LauncherSignature
import InstrumentNewService

verifyLauncherSignature()

let kernel = makeInstrumentNewKernel()
let server = NIOHTTPServer(kernel: kernel)

Task {
    do {
        let env = ProcessInfo.processInfo.environment
        let preferred = Int(env["INSTRUMENT_NEW_PORT"] ?? env["PORT"] ?? "8072") ?? 8072
        var bound: Int
        do {
            bound = try await server.start(port: preferred)
        } catch {
            FileHandle.standardError.write(Data("[instrument-new-service] Port :\(preferred) unavailable (\(error)). Trying ephemeral…\n".utf8))
            bound = try await server.start(port: 0)
        }
        print("instrument-new-service listening on :\(bound)")
        if let pf = env["INSTRUMENT_NEW_PORT_FILE"], !pf.isEmpty {
            try? String(bound).data(using: .utf8)?.write(to: URL(fileURLWithPath: pf))
        }
    } catch {
        FileHandle.standardError.write(Data("[instrument-new-service] Failed to start: \(error)\n".utf8))
    }
}

dispatchMain()

