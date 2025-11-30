import Foundation
import NIO
import NIOHTTP1
import FountainRuntime
import FountainStoreClient
import OpenAPIRuntime
import Crypto
import X509
import LLMGatewayPlugin
import AuthGatewayPlugin
import RateLimiterGatewayPlugin
#if canImport(ChatKitGatewayPlugin)
import ChatKitGatewayPlugin
#endif
#if canImport(GatewayPersonaOrchestrator)
import GatewayPersonaOrchestrator
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTP gateway server that composes plugins for request handling.
/// Provides built-in `/health` and `/metrics` endpoints used for monitoring.
/// Additionally exposes control plane endpoints with basic schema validation.
@MainActor
public final class GatewayServer {
    /// Underlying HTTP server handling TCP connections.
    private var server: NIOHTTPServer
    /// Manages periodic certificate renewal scripts.
    private let manager: CertificateManager
    /// Event loop group powering the SwiftNIO server.
    private let group: EventLoopGroup
    /// Middleware components executed around request routing.
    /// Plugins run in registration order during ``GatewayPlugin.prepare(_:)``
    /// and in reverse order during ``GatewayPlugin.respond(_:for:)``.
    private let plugins: [GatewayPlugin]
    private let zoneManager: ZoneManager?
    private let roleGuardStore: RoleGuardStore?
    private let adminValidator: TokenValidator
    private var routes: [String: RouteInfo]
    private let routesURL: URL?
    private let certificatePath: String?
    private let rateLimiter: RateLimiterGatewayPlugin?
    private let breaker: CircuitBreaker = CircuitBreaker()
    private var roleGuardReloader: RoleGuardConfigReloader?
    private let personaOrchestrator: GatewayPersonaOrchestrator?
#if canImport(ChatKitGatewayPlugin)
    private let chatKitHandlers: ChatKitGeneratedHandlers?
#endif

    private struct ZoneCreateRequest: Codable { let name: String }
    private struct ZonesResponse: Codable { let zones: [ZoneManager.Zone] }
    /// DNS record model supporting core record types.
    private enum RecordType: String, Codable { case A, AAAA, CNAME, MX, TXT, SRV, CAA }
    private struct RecordRequest: Codable { let name: String; let type: RecordType; let value: String }
    private struct RecordsResponse: Codable { let records: [ZoneManager.Record] }

    /// Authentication request and token response models.
    private struct CredentialRequest: Codable { let clientId: String; let clientSecret: String }
    private struct TokenResponse: Codable { let token: String; let expiresAt: String }
    private struct ErrorResponse: Codable { let error: String }

    // Recent traffic ring buffer for control pane
    private actor RecentRequestsStore {
        struct Item: Codable {
            let method: String
            let path: String
            let status: Int
            let durationMs: Int
            let timestamp: String
            let client: String?
        }
        private var items: [Item] = []
        private let limit: Int = 200
        func append(_ item: Item) {
            items.append(item)
            if items.count > limit { items.removeFirst(items.count - limit) }
        }
        func snapshot() -> [Item] { items }
    }

    /// Encodes an error message as JSON and sets the appropriate content type.
    /// - Parameters:
    ///   - status: HTTP status code to return.
    ///   - message: Human-readable error description.
    private func error(_ status: Int, message: String) -> HTTPResponse {
        let body = (try? JSONEncoder().encode(ErrorResponse(error: message))) ?? Data()
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: body)
    }

    /// Route description used for management operations.
    private struct RouteInfo: Codable {
        enum Method: String, Codable, CaseIterable { case GET, POST, PUT, PATCH, DELETE }
        let id: String
        var path: String
        var target: String
        var methods: [Method]
        var rateLimit: Int?
        var proxyEnabled: Bool?
    }



    /// Creates a new gateway server instance.
    /// - Parameters:
    ///   - manager: Certificate renewal manager.
    ///   - plugins: Plugins applied before and after routing.
    ///     Plugins are invoked in the order provided for ``GatewayPlugin.prepare(_:)``
    ///     and in reverse order for ``GatewayPlugin.respond(_:for:)``.
    public init(manager: CertificateManager = CertificateManager(),
                plugins: [GatewayPlugin] = [],
                zoneManager: ZoneManager? = nil,
                routeStoreURL: URL? = nil,
                certificatePath: String? = nil,
                rateLimiter: RateLimiterGatewayPlugin? = nil,
                roleGuardStore: RoleGuardStore? = nil,
                personaOrchestrator: GatewayPersonaOrchestrator? = nil) {
        self.manager = manager
        self.plugins = plugins
        self.zoneManager = zoneManager
        self.roleGuardStore = roleGuardStore
        self.personaOrchestrator = personaOrchestrator
#if canImport(ChatKitGatewayPlugin)
        self.chatKitHandlers = plugins.compactMap { ($0 as? ChatKitGatewayPlugin)?.makeGeneratedHandlers() }.first
#endif
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.routes = [:]
        self.routesURL = routeStoreURL
        self.certificatePath = certificatePath
        self.server = NIOHTTPServer(kernel: HTTPKernel { _ in HTTPResponse(status: 500) }, group: group)
        self.rateLimiter = rateLimiter
        let recentStore = RecentRequestsStore()
        // Initialize admin token validator early
        if let jwksURL = ProcessInfo.processInfo.environment["GATEWAY_JWKS_URL"], let provider = JWKSKeyProvider(jwksURL: jwksURL) {
            self.adminValidator = HMACKeyValidator(keyProvider: provider)
        } else {
            self.adminValidator = HMACKeyValidator()
        }
        // Load persisted routes if configured
        self.reloadRoutes()
        let kernel = HTTPKernel { [plugins, zoneManager, self] req in
            if req.method == "GET" && req.path.split(separator: "?", maxSplits: 1).first == "/admin/recent" {
                let items = await recentStore.snapshot()
                let data = (try? JSONEncoder().encode(items)) ?? Data("[]".utf8)
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
            }
            if req.method == "POST" && req.path.split(separator: "?", maxSplits: 1).first == "/admin/routes/reload" {
                self.reloadRoutes()
                return HTTPResponse(status: 204)
            }
            var request = req
            do {
                for plugin in plugins {
                    request = try await plugin.prepare(request)
                }
            } catch is UnauthorizedError {
                return HTTPResponse(status: 401)
            } catch is ForbiddenError {
                return HTTPResponse(status: 403)
            } catch is TooManyRequestsError {
                return HTTPResponse(status: 429, headers: ["Content-Type": "text/plain"], body: Data("too many requests".utf8))
            } catch is ServiceUnavailableError {
                return HTTPResponse(status: 503, headers: ["Content-Type": "text/plain"], body: Data("service unavailable".utf8))
            }

            if let orchestrator = self.personaOrchestrator {
                let verdict = await orchestrator.decide(for: request)
                switch verdict {
                case .allow:
                    break
                case .deny(let reason, _):
                    return self.error(403, message: reason)
                case .escalate(let reason, _):
                    let json = try? JSONEncoder().encode(["decision": "escalate", "reason": reason])
                    return HTTPResponse(status: 202, headers: ["Content-Type": "application/json"], body: json ?? Data())
                }
            }

            // Allow plugins with routers to handle requests before builtin routes.
            for plugin in plugins {
                if let llm = plugin as? LLMGatewayPlugin,
                   let handled = try await llm.router.route(request) {
                    return handled
                }
                if let auth = plugin as? AuthGatewayPlugin,
                   let handled = try await auth.router.route(request) {
                    return handled
                }
            }

            // Build OpenAPI transport with fallback for non-OpenAPI endpoints and proxying
            let fallback = HTTPKernel { [zoneManager, self] request in
            // Well-known agent descriptor (Store-backed)
            if request.method == "GET", request.path.split(separator: "?", maxSplits: 1).first == "/.well-known/agent-descriptor" {
                let env = ProcessInfo.processInfo.environment
                let corpus = env["AGENT_CORPUS_ID"] ?? env["CORPUS_ID"] ?? "agents"
                guard let agentId = env["AGENT_ID"] ?? env["GATEWAY_AGENT_ID"] else {
                    let msg = ["error": "missing AGENT_ID or GATEWAY_AGENT_ID"]
                    let body = try? JSONSerialization.data(withJSONObject: msg)
                    return HTTPResponse(status: 404, headers: ["Content-Type": "application/json"], body: body ?? Data())
                }
                let key = "agent:\(agentId)"
                let store = GatewayServer.resolveStore()
                if let data = try? await store.getDoc(corpusId: corpus, collection: "agent-descriptors", id: key) {
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
                }
                let msg = ["error": "descriptor not found", "agentId": agentId, "corpus": corpus]
                let body = try? JSONSerialization.data(withJSONObject: msg)
                return HTTPResponse(status: 404, headers: ["Content-Type": "application/json"], body: body ?? Data())
            }
            // Well-known agent facts (PE mappings; Store-backed)
            if request.method == "GET", request.path.split(separator: "?", maxSplits: 1).first == "/.well-known/agent-facts" {
                let env = ProcessInfo.processInfo.environment
                let corpus = env["AGENT_CORPUS_ID"] ?? env["CORPUS_ID"] ?? "agents"
                guard let agentId = env["AGENT_ID"] ?? env["GATEWAY_AGENT_ID"] else {
                    let msg = ["error": "missing AGENT_ID or GATEWAY_AGENT_ID"]
                    let body = try? JSONSerialization.data(withJSONObject: msg)
                    return HTTPResponse(status: 404, headers: ["Content-Type": "application/json"], body: body ?? Data())
                }
                let safeId = agentId.replacingOccurrences(of: "/", with: "|")
                let key = "facts:agent:\(safeId)"
                let store = GatewayServer.resolveStore()
                // Try safe key, then legacy (unsanitized) for backward compatibility
                if let data = try? await store.getDoc(corpusId: corpus, collection: "agent-facts", id: key) {
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
                }
                let legacyKey = "facts:agent:\(agentId)"
                if let data = try? await store.getDoc(corpusId: corpus, collection: "agent-facts", id: legacyKey) {
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
                }
                // Debug payload with attempted keys
                let msg = ["error": "facts not found", "agentId": agentId, "factsId": key, "legacyFactsId": legacyKey, "corpus": corpus]
                let body = try? JSONSerialization.data(withJSONObject: msg)
                return HTTPResponse(status: 404, headers: ["Content-Type": "application/json"], body: body ?? Data())
            }
            if request.path == "/openapi.yaml" {
                let url = URL(fileURLWithPath: "Packages/FountainApps/Sources/gateway-service/openapi.yaml")
                if let data = try? Data(contentsOf: url) {
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
                }
            }
            let segments = request.path.split(separator: "/", omittingEmptySubsequences: true)
                switch (request.method, segments) {
                case ("GET", ["live"]):
                    return self.gatewayLiveness()
                case ("GET", ["ready"]):
                    return self.gatewayReadiness()
                case ("GET", ["roleguard"]):
                    return await self.listRoleGuardRules(request)
                case ("POST", ["roleguard", "reload"]):
                    return await self.reloadRoleGuardRules(request)
                case ("POST", ["routes", "reload"]):
                    self.reloadRoutes()
                    return HTTPResponse(status: 204)
                case ("GET", ["zones"]):
                    if let manager = zoneManager {
                        let zones = await manager.listZones()
                        let json = try JSONEncoder().encode(ZonesResponse(zones: zones))
                        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)
                    } else {
                        return self.error(500, message: "zone manager unavailable")
                    }
                case ("POST", ["zones"]):
                    return await self.createZone(request)
                case ("DELETE", let seg) where seg.count == 2 && seg[0] == "zones":
                    let zoneId = String(seg[1])
                    return await self.deleteZone(zoneId)
                case ("GET", let seg) where seg.count == 3 && seg[0] == "zones" && seg[2] == "records":
                    let zoneId = String(seg[1])
                    return await self.listRecords(zoneId)
                case ("POST", let seg) where seg.count == 3 && seg[0] == "zones" && seg[2] == "records":
                    let zoneId = seg[1]
                    return await self.createRecord(String(zoneId), request: request)
                case ("PUT", let seg) where seg.count == 4 && seg[0] == "zones" && seg[2] == "records":
                    let zoneId = String(seg[1])
                    let recordId = String(seg[3])
                    return await self.updateRecord(zoneId, recordId: recordId, request: request)
                case ("DELETE", let seg) where seg.count == 4 && seg[0] == "zones" && seg[2] == "records":
                    let zoneId = String(seg[1])
                    let recordId = String(seg[3])
                    return await self.deleteRecord(zoneId, recordId: recordId)
                default:
                    if let proxied = try await self.tryProxy(request) {
                        return proxied
                    }
                    return HTTPResponse(status: 404)
                }
            }

            #if canImport(gateway_service)
            let transport = NIOOpenAPIServerTransport(fallback: fallback)
            let api = GatewayOpenAPI(host: self)
            try? api.registerHandlers(on: transport)
            let openapiKernel = transport.asKernel()
            #else
            // When OpenAPI generated module is unavailable (e.g., minimal builds),
            // serve only the fallback routes including well-known descriptor.
            let openapiKernel = fallback
            #endif

            // Handle CORS preflight early for browser-based clients
            if request.method == "OPTIONS" {
                var allowHeaders = request.headers["Access-Control-Request-Headers"] ?? "Content-Type, Authorization"
                if allowHeaders.isEmpty { allowHeaders = "Content-Type, Authorization" }
                return HTTPResponse(
                    status: 204,
                    headers: [
                        "Access-Control-Allow-Origin": request.headers["Origin"] ?? "*",
                        "Access-Control-Allow-Methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS",
                        "Access-Control-Allow-Headers": allowHeaders,
                        "Access-Control-Max-Age": "600"
                    ],
                    body: Data()
                )
            }

            // Enforce auth on metrics (OpenAPI routes) before dispatching
            if request.method == "GET" && request.path.split(separator: "?", maxSplits: 1).first == "/metrics" {
                if let err = await self.requireAdminAuthorization(request) { return err }
            }
            let start = Date()
            var response = try await openapiKernel.handle(request)
            for plugin in plugins.reversed() {
                response = try await plugin.respond(response, for: request)
            }
            // Add default CORS header for browser accessibility
            var headers = response.headers
            if headers["Access-Control-Allow-Origin"] == nil {
                headers["Access-Control-Allow-Origin"] = request.headers["Origin"] ?? "*"
            }
            response.headers = headers
            // Record metrics and emit a structured log line
            await GatewayRequestMetrics.shared.record(method: request.method, status: response.status)
            let durMs = Int(Date().timeIntervalSince(start) * 1000)
            let log: [String: Any] = [
                "ts": ISO8601DateFormatter().string(from: Date()),
                "evt": "http_access",
                "method": request.method,
                "path": request.path,
                "status": response.status,
                "duration_ms": durMs
            ]
            if let data = try? JSONSerialization.data(withJSONObject: log), let line = String(data: data, encoding: .utf8) {
                FileHandle.standardError.write(Data((line + "\n").utf8))
            }
            await recentStore.append(.init(method: request.method,
                                           path: request.path,
                                           status: response.status,
                                           durationMs: durMs,
                                           timestamp: ISO8601DateFormatter().string(from: Date()),
                                           client: request.headers["Authorization"]))
            return response
        }
        self.server = NIOHTTPServer(kernel: kernel, group: group)
        // Kick off RoleGuard config polling if possible
        if let store = roleGuardStore {
            Task { @MainActor in
                let url = await store.configPath
                if let reloader = RoleGuardConfigReloader(store: store, url: url) {
                    self.roleGuardReloader = reloader
                    reloader.start(interval: 2.0)
                }
            }
        }
    }

    // MARK: - Store resolver (local disk → embedded)
    private static func resolveStore() -> FountainStoreClient {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
            let url: URL
            if dir.hasPrefix("~") {
                url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
            } else { url = URL(fileURLWithPath: dir, isDirectory: true) }
            if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) {
            return FountainStoreClient(client: disk)
        }
        return FountainStoreClient(client: EmbeddedFountainStoreClient())
    }

#if canImport(ChatKitGatewayPlugin)
    @MainActor
    func chatKitGeneratedHandlers() -> ChatKitGeneratedHandlers? {
        chatKitHandlers
    }
#else
    @MainActor
    func chatKitGeneratedHandlers() -> ChatKitGeneratedHandlers? {
        nil
    }
#endif

    /// Attempts to match the incoming request against configured routes and proxy it upstream.
    /// Performs a simple prefix match on the configured path and enforces allowed methods.
    /// - Returns: A proxied response if a matching route is found; otherwise `nil`.
    private func tryProxy(_ request: HTTPRequest) async throws -> HTTPResponse? {
        // Extract path without query for matching
        let pathOnly = request.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? request.path
        guard let reqMethod = RouteInfo.Method(rawValue: request.method) else { return nil }
        // Choose the longest matching path prefix among routes
        let candidates = routes.values
            .filter { route in
                (route.methods.isEmpty || route.methods.contains(reqMethod)) &&
                ((route.proxyEnabled ?? true) == true) &&
                (pathOnly == route.path || pathOnly.hasPrefix(route.path.hasSuffix("/") ? route.path : route.path + "/"))
            }
            .sorted { $0.path.count > $1.path.count }
        guard let route = candidates.first else { return nil }

        // Apply rate limiting if a plugin is available
        if let rateLimiter {
            var clientId = "anonymous"
            if let auth = request.headers["Authorization"], auth.hasPrefix("Bearer ") {
                let token = String(auth.dropFirst(7))
                let store = CredentialStore()
                clientId = store.subject(for: token) ?? clientId
            }
            let allowed = await rateLimiter.allow(routeId: route.id, clientId: clientId, limitPerMinute: route.rateLimit)
            if !allowed {
                return HTTPResponse(status: 429, headers: ["Content-Type": "text/plain"], body: Data("too many requests".utf8))
            }
        }

        // Build upstream URL by joining target + suffix (keep original query string)
        let suffix = String(pathOnly.dropFirst(route.path.count))
        let query = request.path.contains("?") ? String(request.path.split(separator: "?", maxSplits: 1)[1]) : nil
        var urlString = route.target
        if !suffix.isEmpty {
            if urlString.hasSuffix("/") || suffix.hasPrefix("/") {
                urlString += suffix
            } else {
                urlString += "/" + suffix
            }
        }
        if let query, !query.isEmpty { urlString += "?" + query }
        guard let url = URL(string: urlString), url.scheme != nil else { return HTTPResponse(status: 502) }
        let breakerKey = "\(route.id)::\(url.scheme ?? "")://\(url.host ?? "")"
        if await !breaker.allow(key: breakerKey) {
            return HTTPResponse(status: 503, headers: ["Content-Type": "text/plain"], body: Data("service unavailable".utf8))
        }
        FileHandle.standardError.write(Data("[gateway] proxy -> \(url.absoluteString)\n".utf8))

        var upstream = URLRequest(url: url)
        upstream.httpMethod = request.method
        // Copy safe headers, let URLSession manage hop-by-hop and payload framing
        for (k, v) in request.headers {
            let lk = k.lowercased()
            if lk == "host" || lk == "content-length" || lk == "transfer-encoding" || lk == "connection" || lk == "expect" { continue }
            upstream.setValue(v, forHTTPHeaderField: k)
        }
        if !request.body.isEmpty { upstream.httpBody = request.body }

        do {
            let (data, resp) = try await URLSession.shared.data(for: upstream)
            await breaker.recordSuccess(key: breakerKey)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 200
            var headers: [String: String] = [:]
            if let http = resp as? HTTPURLResponse {
                for (key, value) in http.allHeaderFields {
                    if let k = key as? String, let v = value as? String { headers[k] = v }
                }
            }
            return HTTPResponse(status: status, headers: headers, body: data)
        } catch {
            await breaker.recordFailure(key: breakerKey)
            return HTTPResponse(status: 502, headers: ["Content-Type": "text/plain"], body: Data("bad gateway".utf8))
        }
    }

    public func gatewayHealth() -> HTTPResponse {
        let json = try? JSONEncoder().encode(["status": "ok"])
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json ?? Data())
    }

    public func gatewayLiveness() -> HTTPResponse {
        let json = try? JSONEncoder().encode(["status": "live"]) 
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json ?? Data())
    }

    public func gatewayReadiness() -> HTTPResponse {
        // In a fuller implementation, check dependencies; for now return ready
        let json = try? JSONEncoder().encode(["status": "ready"]) 
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json ?? Data())
    }

    public func gatewayMetrics() async -> HTTPResponse {
        let exposition = await DNSMetrics.shared.exposition()
        var metrics: [String: Int] = [:]
        for line in exposition.split(separator: "\n") {
            let parts = line.split(separator: " ")
            if parts.count == 2, let value = Int(parts[1]) {
                metrics[String(parts[0])] = value
            }
        }
        let gw = await GatewayRequestMetrics.shared.snapshot()
        for (k, v) in gw { metrics[k] = v }
        let cb = await breaker.metrics()
        for (k, v) in cb { metrics[k] = v }
        // RoleGuard metrics
        let rg = await RoleGuardMetrics.shared.snapshot()
        for (k, v) in rg { metrics[k] = v }
        if let json = try? JSONEncoder().encode(metrics) {
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)
        }
        return HTTPResponse(status: 500)
    }

    private func listRoleGuardRules(_ request: HTTPRequest) async -> HTTPResponse {
        guard let store = roleGuardStore else { return HTTPResponse(status: 404) }
        // Require admin token
        if let err = await requireAdminAuthorization(request) { return err }
        let rules = await store.rules
        if let data = try? JSONEncoder().encode(rules) {
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
        }
        return HTTPResponse(status: 500)
    }

    private func reloadRoleGuardRules(_ request: HTTPRequest) async -> HTTPResponse {
        guard let store = roleGuardStore else { return HTTPResponse(status: 404) }
        // Require admin token
        if let err = await requireAdminAuthorization(request) { return err }
        let ok = await store.reload()
        if ok {
            let count = (await store.rules).count
            Task { await RoleGuardMetrics.shared.recordReload(ruleCount: count) }
        }
        return HTTPResponse(status: ok ? 204 : 304)
    }

    /// Verifies that the request carries an admin-capable token.
    /// Returns a ready error response when unauthorized/forbidden, or nil if authorized.
    private func requireAdminAuthorization(_ request: HTTPRequest) async -> HTTPResponse? {
        guard let auth = request.headers["Authorization"], auth.hasPrefix("Bearer ") else {
            Task { await RoleGuardMetrics.shared.recordUnauthorized() }
            return HTTPResponse(status: 401)
        }
        let token = String(auth.dropFirst(7))
        guard let claims = await adminValidator.validate(token: token) else {
            Task { await RoleGuardMetrics.shared.recordUnauthorized() }
            return HTTPResponse(status: 401)
        }
        let scopes = Set(claims.scopes)
        if claims.role == "admin" || scopes.contains("admin") {
            return nil
        }
        Task { await RoleGuardMetrics.shared.recordForbidden() }
        return HTTPResponse(status: 403)
    }

    public func issueAuthToken(_ request: HTTPRequest) async -> HTTPResponse {
        do {
            let creds = try JSONDecoder().decode(CredentialRequest.self, from: request.body)
            let store = CredentialStore()
            guard store.validate(clientId: creds.clientId, clientSecret: creds.clientSecret) else {
                let json = try JSONEncoder().encode(ErrorResponse(error: "invalid credentials"))
                return HTTPResponse(status: 401, headers: ["Content-Type": "application/json"], body: json)
            }
            let expiry = Date().addingTimeInterval(3600)
            let formatter = ISO8601DateFormatter()
            let expires = formatter.string(from: expiry)
            let role = store.role(forClientId: creds.clientId)
            guard let token = try? store.signJWT(subject: creds.clientId, expiresAt: expiry, role: role) else {
                return HTTPResponse(status: 500)
            }
            let json = try JSONEncoder().encode(TokenResponse(token: token, expiresAt: expires))
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)
        } catch {
            return HTTPResponse(status: 400)
        }
    }

    public func certificateInfo() -> HTTPResponse {
        struct CertificateInfo: Codable { let notAfter: String; let issuer: String }
        guard let path = certificatePath else { return HTTPResponse(status: 500) }
        guard FileManager.default.fileExists(atPath: path) else { return HTTPResponse(status: 404) }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let cert: X509.Certificate
            if let pem = String(data: data, encoding: .utf8), pem.contains("-----BEGIN") {
                cert = try X509.Certificate(pemEncoded: pem)
            } else {
                cert = try X509.Certificate(derEncoded: [UInt8](data))
            }
            let formatter = ISO8601DateFormatter()
            let info = CertificateInfo(
                notAfter: formatter.string(from: cert.notValidAfter),
                issuer: cert.issuer.description
            )
            if let json = try? JSONEncoder().encode(info) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)
            }
            return HTTPResponse(status: 500)
        } catch {
            return HTTPResponse(status: 500)
        }
    }

    public func renewCertificate() -> HTTPResponse {
        manager.triggerNow()
        if let json = try? JSONEncoder().encode(["status": "triggered"]) {
            return HTTPResponse(status: 202, headers: ["Content-Type": "application/json"], body: json)
        }
        return HTTPResponse(status: 500)
    }

    public func listRoutes() -> HTTPResponse {
        if let json = try? JSONEncoder().encode(Array(self.routes.values)) {
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)
        }
        return HTTPResponse(status: 500)
    }

    public func createRoute(_ request: HTTPRequest) -> HTTPResponse {
        do {
            let info = try JSONDecoder().decode(RouteInfo.self, from: request.body)
            if !info.methods.allSatisfy({ RouteInfo.Method.allCases.contains($0) }) {
                return HTTPResponse(status: 400)
            }
            if self.routes[info.id] == nil {
                self.routes[info.id] = info
                self.persistRoutes()
                let json = try JSONEncoder().encode(info)
                return HTTPResponse(status: 201, headers: ["Content-Type": "application/json"], body: json)
            }
            let json = try JSONEncoder().encode(ErrorResponse(error: "exists"))
            return HTTPResponse(status: 409, headers: ["Content-Type": "application/json"], body: json)
        } catch {
            return HTTPResponse(status: 400)
        }
    }

    public func updateRoute(_ routeId: String, request: HTTPRequest) -> HTTPResponse {
        guard self.routes[routeId] != nil else {
            if let json = try? JSONEncoder().encode(ErrorResponse(error: "not found")) {
                return HTTPResponse(status: 404, headers: ["Content-Type": "application/json"], body: json)
            }
            return HTTPResponse(status: 404)
        }
        do {
            let info = try JSONDecoder().decode(RouteInfo.self, from: request.body)
            guard info.methods.allSatisfy({ RouteInfo.Method.allCases.contains($0) }) else {
                return HTTPResponse(status: 400)
            }
            let updated = RouteInfo(id: routeId, path: info.path, target: info.target, methods: info.methods, rateLimit: info.rateLimit, proxyEnabled: info.proxyEnabled)
            self.routes[routeId] = updated
            self.persistRoutes()
            let json = try JSONEncoder().encode(updated)
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)
        } catch {
            return HTTPResponse(status: 400)
        }
    }

    public func deleteRoute(_ routeId: String) -> HTTPResponse {
        if self.routes.removeValue(forKey: routeId) != nil {
            self.persistRoutes()
            return HTTPResponse(status: 204)
        }
        if let json = try? JSONEncoder().encode(ErrorResponse(error: "not found")) {
            return HTTPResponse(status: 404, headers: ["Content-Type": "application/json"], body: json)
        }
        return HTTPResponse(status: 404)
    }

    private func persistRoutes() {
        guard let url = routesURL else { return }
        do {
            let list = Array(self.routes.values)
            let data = try JSONEncoder().encode(list)
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let temp = dir.appendingPathComponent(UUID().uuidString)
            try data.write(to: temp)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: url)
            }
        } catch {
            FileHandle.standardError.write(Data("[gateway] Warning: failed to persist routes to \(url.path): \(error)\n".utf8))
        }
    }

    public func reloadRoutes() {
        guard let url = routesURL else { return }
        do {
            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder().decode([RouteInfo].self, from: data)
            self.routes = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        } catch {
            FileHandle.standardError.write(Data("[gateway] Warning: failed to reload routes from \(url.path): \(error)\n".utf8))
        }
    }

    public func createZone(_ request: HTTPRequest) async -> HTTPResponse {
        guard let manager = zoneManager else { return self.error(500, message: "zone manager unavailable") }
        do {
            let req = try JSONDecoder().decode(ZoneCreateRequest.self, from: request.body)
            let zone = try await manager.createZone(name: req.name)
            let json = try JSONEncoder().encode(zone)
            return HTTPResponse(status: 201, headers: ["Content-Type": "application/json"], body: json)
        } catch {
            return self.error(400, message: "invalid zone data")
        }
    }

    public func deleteZone(_ zoneId: String) async -> HTTPResponse {
        guard let manager = zoneManager else { return self.error(500, message: "zone manager unavailable") }
        guard let id = UUID(uuidString: zoneId) else { return self.error(404, message: "zone not found") }
        if let success = try? await manager.deleteZone(id: id), success {
            return HTTPResponse(status: 204)
        }
        return self.error(404, message: "zone not found")
    }

    public func listRecords(_ zoneId: String) async -> HTTPResponse {
        guard let manager = zoneManager else { return self.error(500, message: "zone manager unavailable") }
        guard let id = UUID(uuidString: zoneId) else { return self.error(404, message: "zone not found") }
        if let recs = await manager.listRecords(zoneId: id) {
            if let json = try? JSONEncoder().encode(RecordsResponse(records: recs)) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)
            }
            return self.error(500, message: "failed to encode records")
        }
        return self.error(404, message: "zone not found")
    }

    public func createRecord(_ zoneId: String, request: HTTPRequest) async -> HTTPResponse {
        guard let manager = zoneManager else { return self.error(500, message: "zone manager unavailable") }
        guard let id = UUID(uuidString: zoneId) else { return self.error(404, message: "zone not found") }
        do {
            let req = try JSONDecoder().decode(RecordRequest.self, from: request.body)
            if let record = try await manager.createRecord(zoneId: id, name: req.name, type: req.type.rawValue, value: req.value),
               let json = try? JSONEncoder().encode(record) {
                return HTTPResponse(status: 201, headers: ["Content-Type": "application/json"], body: json)
            }
            return self.error(404, message: "zone not found")
        } catch {
            return self.error(400, message: "invalid record data")
        }
    }

    public func updateRecord(_ zoneId: String, recordId: String, request: HTTPRequest) async -> HTTPResponse {
        guard let manager = zoneManager else { return self.error(500, message: "zone manager unavailable") }
        guard let zid = UUID(uuidString: zoneId), let rid = UUID(uuidString: recordId) else {
            return self.error(404, message: "record not found")
        }
        do {
            let req = try JSONDecoder().decode(RecordRequest.self, from: request.body)
            if let record = try await manager.updateRecord(zoneId: zid, recordId: rid, name: req.name, type: req.type.rawValue, value: req.value),
               let json = try? JSONEncoder().encode(record) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)
            }
            return self.error(404, message: "record not found")
        } catch {
            return self.error(400, message: "invalid record data")
        }
    }

    public func deleteRecord(_ zoneId: String, recordId: String) async -> HTTPResponse {
        guard let manager = zoneManager else { return self.error(500, message: "zone manager unavailable") }
        guard let zid = UUID(uuidString: zoneId), let rid = UUID(uuidString: recordId) else {
            return self.error(404, message: "record not found")
        }
        if let success = try? await manager.deleteRecord(zoneId: zid, recordId: rid), success {
            return HTTPResponse(status: 204)
        }
        return self.error(404, message: "record not found")
    }

    /// Starts the gateway on the given port.
    /// Begins certificate renewal scheduling before binding the SwiftNIO server.
    /// - Parameter port: TCP port to bind.
    public func start(port: Int = 8080) async throws {
        _ = try await startAndReturnPort(port: port)
    }

    /// Starts the gateway and returns the bound port (helpful for tests using port 0).
    public func startAndReturnPort(port: Int = 8080) async throws -> Int {
        manager.start()
        let bound = try await server.start(port: port)
        return bound
    }

    /// Stops the server and terminates certificate renewal.
    /// Cancels the certificate manager timer and shuts down the server.
    public func stop() async throws {
        manager.stop()
        try await server.stop()
        roleGuardReloader?.stop()
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
