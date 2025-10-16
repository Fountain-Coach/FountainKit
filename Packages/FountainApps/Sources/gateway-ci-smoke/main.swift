import Foundation
import GatewayAPI
import ApiClientsCore
import OpenAPIRuntime
import OpenAPIURLSession
import Crypto

@main
enum GatewayCISmoke {

    enum SmokeError: Error, CustomStringConvertible {
        case emptyHealth
        case missingMetric(String)
        case unexpectedResponse(String)
        case emptySessionSecret
        case refreshDidNotRotate
        case unexpectedMessageStatus
        case missingAnswer
        case missingThreadIdentifier
        case emptyThreadList
        case missingThreadMessages

        var description: String {
            switch self {
            case .emptyHealth:
                return "gateway health payload was empty"
            case .missingMetric(let name):
                return "metrics response missing \(name)"
            case .unexpectedResponse(let context):
                return "unexpected response: \(context)"
            case .emptySessionSecret:
                return "chatkit session secret missing"
            case .refreshDidNotRotate:
                return "chatkit refresh did not rotate secret"
            case .unexpectedMessageStatus:
                return "chatkit message response returned unexpected status"
            case .missingAnswer:
                return "chatkit message response missing answer"
            case .missingThreadIdentifier:
                return "chatkit thread identifier missing"
            case .emptyThreadList:
                return "chatkit thread list returned no entries"
            case .missingThreadMessages:
                return "chatkit thread payload did not include messages"
            }
        }
    }

    static func main() async {
        do {
            try await runSmoke()
            print("[gateway-ci-smoke] ✅ completed")
        } catch {
            fputs("[gateway-ci-smoke] ❌ \(error)\n", stderr)
            exit(1)
        }
    }

    private static func runSmoke() async throws {
        let env = ProcessInfo.processInfo.environment
        let baseURLString = env["GATEWAY_BASE_URL"] ?? "http://127.0.0.1:8010"
        guard let baseURL = URL(string: baseURLString) else {
            throw SmokeError.unexpectedResponse("invalid base URL: \(baseURLString)")
        }

        let adminToken = try makeAdminToken(secret: env["GATEWAY_JWT_SECRET"] ?? "secret")
        let gatewayClient = GatewayClient(
            baseURL: baseURL,
            defaultHeaders: ["Authorization": "Bearer \(adminToken)"]
        )

        print("[gateway-ci-smoke] Probing /health…")
        let health = try await gatewayClient.health()
        guard !health.value.isEmpty else { throw SmokeError.emptyHealth }

        print("[gateway-ci-smoke] Probing /metrics…")
        let metrics = try await gatewayClient.metrics()
        guard metrics["gateway_requests_total"] != nil else {
            throw SmokeError.missingMetric("gateway_requests_total")
        }

        let transport = URLSessionTransport()
        let middlewares = APIClientHelpers.defaultMiddlewares()
        let openapiClient = GatewayAPI.Client(
            serverURL: baseURL,
            transport: transport,
            middlewares: middlewares
        )

        print("[gateway-ci-smoke] Creating ChatKit session…")
        let sessionOutput = try await openapiClient.startChatKitSession(.init())
        guard case .created(let created) = sessionOutput else {
            throw SmokeError.unexpectedResponse("startChatKitSession returned \(sessionOutput)")
        }
        var session = try created.body.json
        guard !session.client_secret.isEmpty else { throw SmokeError.emptySessionSecret }
        let originalSecret = session.client_secret

        print("[gateway-ci-smoke] Refreshing ChatKit session…")
        let refreshInput = Operations.refreshChatKitSession.Input(
            body: .json(.init(client_secret: session.client_secret))
        )
        let refreshOutput = try await openapiClient.refreshChatKitSession(refreshInput)
        guard case .ok(let refreshedOK) = refreshOutput else {
            throw SmokeError.unexpectedResponse("refreshChatKitSession returned \(refreshOutput)")
        }
        session = try refreshedOK.body.json
        let activeSecret = session.client_secret
        guard !activeSecret.isEmpty else { throw SmokeError.emptySessionSecret }
        guard activeSecret != originalSecret else {
            throw SmokeError.refreshDidNotRotate
        }

        print("[gateway-ci-smoke] Posting ChatKit message…")
        let messageMetadata = Components.Schemas.ChatKitMessageRequest.metadataPayload(
            additionalProperties: ["suite": "gateway-ci-smoke"]
        )
        let messageBody = Components.Schemas.ChatKitMessageRequest(
            client_secret: activeSecret,
            thread_id: nil,
            messages: [
                .init(
                    id: nil,
                    role: .user,
                    content: "Hello from gateway-ci-smoke at \(ISO8601DateFormatter().string(from: Date()))",
                    created_at: nil,
                    attachments: nil
                )
            ],
            stream: false,
            metadata: messageMetadata
        )
        let messageOutput = try await openapiClient.postChatKitMessage(
            .init(body: .json(messageBody))
        )
        guard case .ok(let okMessage) = messageOutput else {
            throw SmokeError.unexpectedMessageStatus
        }
        let messageResponse = try okMessage.body.json
        guard !messageResponse.answer.isEmpty else { throw SmokeError.missingAnswer }
        guard !messageResponse.thread_id.isEmpty else { throw SmokeError.missingThreadIdentifier }

        let threadId = messageResponse.thread_id

        print("[gateway-ci-smoke] Listing ChatKit threads…")
        let listOutput = try await openapiClient.listChatKitThreads(
            .init(query: .init(client_secret: activeSecret))
        )
        guard case .ok(let okList) = listOutput else {
            throw SmokeError.unexpectedResponse("listChatKitThreads returned \(listOutput)")
        }
        let threads = try okList.body.json.threads
        guard let firstThread = threads.first(where: { $0.thread_id == threadId }) else {
            throw SmokeError.emptyThreadList
        }
        guard firstThread.message_count > 0 else { throw SmokeError.emptyThreadList }

        print("[gateway-ci-smoke] Fetching ChatKit thread…")
        let getOutput = try await openapiClient.getChatKitThread(
            .init(
                path: .init(threadId: threadId),
                query: .init(client_secret: activeSecret)
            )
        )
        guard case .ok(let okThread) = getOutput else {
            throw SmokeError.unexpectedResponse("getChatKitThread returned \(getOutput)")
        }
        let thread = try okThread.body.json
        guard !thread.messages.isEmpty else { throw SmokeError.missingThreadMessages }

        print("[gateway-ci-smoke] Deleting ChatKit thread…")
        let deleteOutput = try await openapiClient.deleteChatKitThread(
            .init(
                path: .init(threadId: threadId),
                query: .init(client_secret: activeSecret)
            )
        )
        guard case .noContent = deleteOutput else {
            throw SmokeError.unexpectedResponse("deleteChatKitThread returned \(deleteOutput)")
        }
    }

    private static func makeAdminToken(secret: String) throws -> String {
        struct Header: Encodable { let alg = "HS256"; let typ = "JWT" }
        struct Payload: Encodable {
            let sub: String
            let exp: Int
            let role: String
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let header = try encoder.encode(Header())
        let payload = try encoder.encode(
            Payload(
                sub: "gateway-ci-smoke",
                exp: Int(Date().addingTimeInterval(900).timeIntervalSince1970),
                role: "admin"
            )
        )
        let signingInput = "\(header.base64URLEncodedString()).\(payload.base64URLEncodedString())"
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(signingInput.utf8),
            using: key
        )
        return "\(signingInput).\(Data(signature).base64URLEncodedString())"
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
