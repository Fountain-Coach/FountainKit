import Foundation
import Dispatch
import PublishingFrontend
import FountainRuntime
import LLMGatewayPlugin
import AuthGatewayPlugin
import RateLimiterGatewayPlugin
import CuratorGatewayPlugin
import LauncherSignature
import GatewayPersonaOrchestrator
import FountainStoreClient

verifyLauncherSignature()
// Role guard plugin in this target
// Loaded from config if present
let env = ProcessInfo.processInfo.environment
let configStore = ConfigurationStore.fromEnvironment(env)

let publishingConfig = try? loadPublishingConfig(store: configStore, environment: env)
if publishingConfig == nil {
    FileHandle.standardError.write(Data("[gateway] Warning: failed to load publishing config; using defaults for static content.\n".utf8))
}

let gatewayConfig = try? loadGatewayConfig(store: configStore, environment: env)
if gatewayConfig == nil {
    FileHandle.standardError.write(Data("[gateway] Warning: failed to load gateway config; using defaults for rate limiting.\n".utf8))
}
let rateLimiter = RateLimiterGatewayPlugin(defaultLimit: gatewayConfig?.rateLimitPerMinute ?? 60)
let curatorPlugin = CuratorGatewayPlugin()
let llmPlugin = LLMGatewayPlugin()
let authPlugin = AuthGatewayPlugin()
var routesURL: URL?
if let data = configStore?.getSync("routes.json") {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("routes.json")
    try? data.write(to: tmp)
    routesURL = tmp
} else {
    let path = env["ROUTES_PATH"] ?? "Configuration/routes.json"
    routesURL = URL(fileURLWithPath: path)
}
var plugins: [any GatewayPlugin] = []
let roleRules = loadRoleGuardRules(store: configStore, environment: env)
let roleGuardStore = RoleGuardStore(initialRules: roleRules, configURL: nil)
Task { await RoleGuardMetrics.shared.setActiveRules(roleRules.count) }
// Choose validator based on environment (JWKS for HS256-oct if provided; otherwise env secret)
if let jwksURL = env["GATEWAY_JWKS_URL"], let provider = JWKSKeyProvider(jwksURL: jwksURL) {
    plugins.append(RoleGuardPlugin(store: roleGuardStore, validator: HMACKeyValidator(keyProvider: provider)))
} else {
    plugins.append(RoleGuardPlugin(store: roleGuardStore, validator: HMACKeyValidator()))
}
plugins.append(contentsOf: [
    authPlugin as any GatewayPlugin,
    curatorPlugin as any GatewayPlugin,
    llmPlugin as any GatewayPlugin,
    rateLimiter as any GatewayPlugin,
    LoggingPlugin() as any GatewayPlugin,
    PublishingFrontendPlugin(rootPath: publishingConfig?.rootPath ?? "./Public") as any GatewayPlugin
])
let orchestrator = GatewayPersonaOrchestrator(personas: [
    SecuritySentinelPersona(),
    DestructiveGuardianPersona()
])

let server = GatewayServer(plugins: plugins, zoneManager: nil, routeStoreURL: routesURL, certificatePath: nil, rateLimiter: rateLimiter, roleGuardStore: roleGuardStore, personaOrchestrator: orchestrator)
Task { @MainActor in
    let port = Int(env["GATEWAY_PORT"] ?? env["PORT"] ?? "8010") ?? 8010
    try await server.start(port: port)
}

if CommandLine.arguments.contains("--dns") {
    Task {
        let zoneURL = URL(fileURLWithPath: "Configuration/zones.yml")
        if let manager = try? ZoneManager(fileURL: zoneURL) {
            let dns = await DNSServer(zoneManager: manager)
            do {
                try await dns.start(udpPort: 1053)
            } catch {
                FileHandle.standardError.write(Data("[gateway] Warning: DNS failed to start on port 1053: \(error)\n".utf8))
            }
        } else {
            FileHandle.standardError.write(Data("[gateway] Warning: failed to initialize ZoneManager\n".utf8))
        }
    }
}

dispatchMain()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
