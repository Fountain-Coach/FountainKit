import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import AudioTalkAPI

@main
enum AudioTalkCISmoke {
    enum SmokeError: Error, CustomStringConvertible {
        case invalidBase
        case unexpected(String)
        case missingETag
        var description: String {
            switch self {
            case .invalidBase: return "invalid base URL"
            case .unexpected(let c): return "unexpected response: \(c)"
            case .missingETag: return "missing ETag"
            }
        }
    }

    static func main() async {
        do {
            try await run()
            print("[audiotalk-ci-smoke] ✅ completed")
        } catch {
            fputs("[audiotalk-ci-smoke] ❌ \(error)\n", stderr)
            exit(1)
        }
    }

    static func run() async throws {
        let env = ProcessInfo.processInfo.environment
        let baseURLString = env["AUDIOTALK_BASE_URL"] ?? "http://127.0.0.1:8080"
        guard let baseURL = URL(string: baseURLString) else { throw SmokeError.invalidBase }
        let client = AudioTalkAPI.Client(serverURL: baseURL, transport: URLSessionTransport())

        // Health
        guard case .ok = try await client.getAudioTalkHealth(.init()) else { throw SmokeError.unexpected("health") }

        // Dictionary upsert/list
        let upReq = Components.Schemas.DictionaryUpsertRequest(items: [.init(token: "smoke", value: "ok", description: nil)])
        guard case .ok = try await client.upsertDictionary(.init(body: .json(upReq))) else { throw SmokeError.unexpected("upsert") }
        guard case .ok(let listOK) = try await client.listDictionary(.init()), case .json(let list) = listOK.body, list.items.contains(where: { $0.token == "smoke" }) else {
            throw SmokeError.unexpected("list")
        }

        // Notation session and ETag flow
        guard case .created(let created) = try await client.createNotationSession(.init()), case .json(let sess) = created.body else {
            throw SmokeError.unexpected("create notation session")
        }
        let id = sess.id
        guard case .ok(let getOK) = try await client.getLilySource(.init(path: .init(id: id))), let etag = getOK.headers.ETag else {
            throw SmokeError.missingETag
        }
        // Wrong If-Match
        guard case .preconditionFailed = try await client.putLilySource(.init(path: .init(id: id), headers: .init(If_hyphen_Match: "wrong"), body: .plainText(HTTPBody("% bad")))) else {
            throw SmokeError.unexpected("put 412")
        }
        // Correct If-Match
        guard case .ok(let putOK) = try await client.putLilySource(.init(path: .init(id: id), headers: .init(If_hyphen_Match: etag), body: .plainText(HTTPBody("% lily\n c'4")))), putOK.headers.ETag != nil else {
            throw SmokeError.unexpected("put 200")
        }
    }
}

