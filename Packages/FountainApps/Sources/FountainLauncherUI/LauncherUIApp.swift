import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit
#if canImport(EngraverStudio)
import EngraverStudio
import EngraverChatCore
#endif

@main
struct LauncherUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var vm = LauncherViewModel()
    var body: some Scene {
        WindowGroup {
            ContentView(vm: vm)
                .onAppear {
                    // Ensure the window comes to the foreground when launched from Terminal
                    if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
                }
        }
        .commands {
            CommandMenu("View") {
                Button("Control") { vm.tab = .control }.keyboardShortcut("1")
                if #available(macOS 13.0, *) {
                    #if canImport(EngraverStudio)
                    Button("Engraver Studio") { vm.tab = .engraver }.keyboardShortcut("2")
                    #endif
                    Button("AudioTalk Studio") { vm.tab = .audiotalk }.keyboardShortcut("3")
                }
            }
            CommandMenu("Profile") {
                Button(action: { vm.runProfile = .audioTalk }) { Text(vm.runProfile == .audioTalk ? "✓ AudioTalk Only" : "AudioTalk Only") }
                Button(action: { vm.runProfile = .fullStack }) { Text(vm.runProfile == .fullStack ? "✓ Full Fountain" : "Full Fountain") }
            }
            CommandMenu("AudioTalk") {
                Button("Start Stack") { vm.startAudioTalkStack() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Stop Stack") { vm.stopAudioTalkStack() }.keyboardShortcut("x", modifiers: [.command, .shift])
                Button("Kill All") { vm.killAudioTalkAll() }.keyboardShortcut("k", modifiers: [.command, .shift])
                Divider()
                Button("Precompile") { vm.precompileAudioTalk() }.keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Menu("Open Logs") {
                    Button("AudioTalk") { vm.openAudioTalkLog("audiotalk") }
                    Button("Function Caller") { vm.openAudioTalkLog("function-caller") }
                    Button("Tools Factory") { vm.openAudioTalkLog("tools-factory") }
                }
                Menu("Show Logs Panel") {
                    Button("AudioTalk") { vm.showAudioTalkLog = true }
                    Button("Function Caller") { vm.showFunctionCallerLog = true }
                    Button("Tools Factory") { vm.showToolsFactoryLog = true }
                }
            }
            CommandMenu("Full Stack") {
                Button("Start Full Stack") { vm.startFullStack() }
                Button("Stop Full Stack") { vm.stopFullStack() }
                Button("Kill Full Stack") { vm.killFullStack() }
                Divider()
                Button("Precompile Full Stack") { vm.precompileFullStack() }
                Divider()
                Menu("Open Logs") {
                    Button("Gateway") { vm.openRepoLog("gateway") }
                    Button("Planner") { vm.openRepoLog("planner") }
                    Button("Persist") { vm.openRepoLog("persist") }
                    Button("Awareness") { vm.openRepoLog("baseline-awareness") }
                    Button("Bootstrap") { vm.openRepoLog("bootstrap") }
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }
}

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var repoPath: String? {
        didSet { UserDefaults.standard.set(repoPath, forKey: Self.repoKey) }
    }
    @Published var starting: Bool = false
    @Published var running: Bool = false
    @Published var controlPlaneOK: Bool = false
    @Published var logText: String = ""
    @Published var errorMessage: String? = nil
    @Published var services: [CPServiceStatus] = []
    // AudioTalk stack runtime metadata (PIDs and ports)
    @Published var audiotalkPID: String? = nil
    @Published var functionCallerPID: String? = nil
    @Published var toolsFactoryPID: String? = nil
    @Published var audioTalkPort: Int = 8080
    @Published var functionCallerPort: Int = 8004
    @Published var toolsFactoryPort: Int = 8011
    // Live service logs and toggles
    @Published var audiotalkLog: String = ""
    @Published var functionCallerLog: String = ""
    @Published var toolsFactoryLog: String = ""
    @Published var showAudioTalkLog: Bool = false
    @Published var showFunctionCallerLog: Bool = false
    @Published var showToolsFactoryLog: Bool = false
    enum Tab { case control, engraver, audiotalk }
    @Published var tab: Tab = .control

    private var tailProc: Process?
    private var statusTimer: Timer?
    enum BuildMode: Hashable { case auto, noBuild, forceBuild }
    @Published var buildMode: BuildMode = .auto
    @Published var followTailMain: Bool = true

    enum RunProfile: String { case audioTalk, fullStack }
    @AppStorage("FountainLauncher.RunProfile") var runProfile: RunProfile = .fullStack

    static let repoKey = "FountainAI.RepoRoot"
    private var ctrlURL: URL

    init() {
        let env = ProcessInfo.processInfo.environment
        if let envRoot = env["FOUNTAINKIT_ROOT"], !envRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            repoPath = envRoot
        } else if let saved = UserDefaults.standard.string(forKey: Self.repoKey), !saved.isEmpty {
            repoPath = saved
        }
        // Determine default ports from environment for display (use raw env; processEnv requires full init)
        audioTalkPort = Int(env["AUDIOTALK_PORT"] ?? env["PORT"] ?? "8080") ?? 8080
        functionCallerPort = Int(env["FUNCTION_CALLER_PORT"] ?? "8004") ?? 8004
        toolsFactoryPort = Int(env["TOOLS_FACTORY_PORT"] ?? "8011") ?? 8011
        // Choose status URL based on profile (AudioTalk health vs control-plane status)
        let audioStudio = env["AUDIO_TALK_STUDIO"].map { ["1","true","yes"].contains($0.lowercased()) } ?? false
        let storedProfileRaw = UserDefaults.standard.string(forKey: "FountainLauncher.RunProfile")
        let storedProfile: RunProfile = RunProfile(rawValue: storedProfileRaw ?? "") ?? .audioTalk
        if storedProfile == .audioTalk || audioStudio {
            let port = Int(env["AUDIOTALK_PORT"] ?? env["PORT"] ?? "8080") ?? 8080
            ctrlURL = URL(string: "http://127.0.0.1:\(port)/audiotalk/meta/health")!
            tab = .audiotalk
        } else {
            ctrlURL = URL(string: "http://127.0.0.1:9090/status")!
        }
        if let auto = env["AUDIO_TALK_AUTOSTART"], ["1","true","yes"].contains(auto.lowercased()), repoPath != nil {
            let env = processEnv()
            let storedProfileRaw = UserDefaults.standard.string(forKey: "FountainLauncher.RunProfile")
            let storedProfile: RunProfile = RunProfile(rawValue: storedProfileRaw ?? "") ?? .fullStack
            if storedProfile == .fullStack {
                runStreaming(command: ["bash", "Scripts/dev-up", "--check"], cwd: repoPath!, env: env)
            } else {
                runStreaming(command: ["bash", "Scripts/audiotalk-dev-up.sh"], cwd: repoPath!, env: env)
            }
        }
        startStatusPolling()
        startTailingLogs()
        refreshAudioTalkPIDs(); updateServiceLogs()
    }

    func chooseRepo() {
        let panel = NSOpenPanel()
        panel.message = "Select the FountainAI repository root"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            let pkg = url.appendingPathComponent("Package.swift")
            guard FileManager.default.fileExists(atPath: pkg.path) else {
                errorMessage = "Selected folder is not a FountainAI repo (missing Package.swift)"
                return
            }
            if LauncherResources.locateSpecDirectory(repoRoot: url.path) == nil {
                errorMessage = "Selected folder is missing Fountain specs (looked for Packages/FountainSpecCuration/openapi or openapi/)"
                return
            }
            if LauncherResources.locateScriptsDirectory(repoRoot: url.path) == nil {
                errorMessage = "Selected folder is missing launcher Scripts/."
                return
            }
            repoPath = url.path
            startTailingLogs(reset: true)
        }
    }

    func start() {
        guard let repoPath else { errorMessage = "Select repository first"; return }
        starting = true
        let env = processEnv()
        guard let script = LauncherResources.launcherScriptURL(repoRoot: repoPath, environment: env) else {
            errorMessage = "Launcher script not found in Scripts/"
            starting = false
            return
        }
        var args = ["bash", script.path, "start"]
        switch buildMode { case .auto: break; case .noBuild: args.append("--no-build"); case .forceBuild: args.append("--force-build") }
        run(command: args, cwd: repoPath, env: env) { [weak self] code, out in
            Task { @MainActor in
                self?.starting = false
                if code == 0 { self?.controlPlaneOK = true } else { self?.errorMessage = "Start failed. Check logs." }
            }
        }
    }

    func stop() {
        guard let repoPath else { return }
        let env = processEnv()
        guard let script = LauncherResources.launcherScriptURL(repoRoot: repoPath, environment: env) else { return }
        run(command: ["bash", script.path, "stop"], cwd: repoPath, env: env) { [weak self] _, _ in
            Task { @MainActor in self?.controlPlaneOK = false }
        }
    }

    func diagnostics() {
        guard let repoPath else { errorMessage = "Select repository first"; return }
        let env = processEnv()
        if let script = LauncherResources.diagnosticsScriptURL(repoRoot: repoPath, environment: env) {
            runStreaming(command: ["swift", script.path], cwd: repoPath, env: env)
        } else {
            // Fallback: probe control plane
            Task { [weak self] in
                do {
                    _ = try await URLSession.shared.data(from: self!.ctrlURL)
                    await MainActor.run { self?.presentAlert(title: "Diagnostics", message: "Control plane reachable.") }
                } catch {
                    await MainActor.run { self?.presentAlert(title: "Diagnostics", message: "Control plane not reachable.") }
                }
            }
        }
    }

    // MARK: - AudioTalk helpers
    func startAudioTalkServer() {
        guard let repoPath else { errorMessage = "Select repository first"; return }
        let env = processEnv()
        runStreaming(command: ["swift", "run", "--package-path", "Packages/FountainApps", "audiotalk-server"], cwd: repoPath, env: env)
    }
    func startAudioTalkStack() {
        guard let repoPath else { errorMessage = "Select repository first"; return }
        let env = processEnv()
        runStreaming(command: ["bash", "Scripts/audiotalk-dev-up.sh"], cwd: repoPath, env: env)
    }
    func stopAudioTalkStack() {
        guard let repoPath else { errorMessage = "Select repository first"; return }
        let env = processEnv()
        runStreaming(command: ["bash", "Scripts/audiotalk-dev-down.sh"], cwd: repoPath, env: env)
    }
    func precompileAudioTalk() {
        guard let repoPath else { errorMessage = "Select repository first"; return }
        let env = processEnv()
        // Precompile the three products to minimize concurrent SwiftPM rebuilds on run
        runStreaming(command: ["swift", "build", "--configuration", "debug", "--package-path", "Packages/FountainApps", "--product", "audiotalk-server", "--product", "tools-factory-server", "--product", "function-caller-server"], cwd: repoPath, env: env)
    }
    // Full stack
    func startFullStack() {
        guard let repoPath else { errorMessage = "Select repository first"; return }
        runStreaming(command: ["bash", "Scripts/dev-up", "--check"], cwd: repoPath, env: processEnv())
    }
    func stopFullStack() {
        guard let repoPath else { return }
        runStreaming(command: ["bash", "Scripts/dev-down"], cwd: repoPath, env: processEnv())
    }
    func killFullStack() {
        guard let repoPath else { return }
        runStreaming(command: ["bash", "Scripts/dev-down"], cwd: repoPath, env: processEnv())
    }
    func precompileFullStack() {
        guard let repoPath else { return }
        runStreaming(command: ["bash", "Scripts/dev-up", "prebuild", "--all"], cwd: repoPath, env: processEnv())
    }
    func startToolsFactory() {
        guard let repoPath else { errorMessage = "Select repository first"; return }
        let env = processEnv()
        runStreaming(command: ["swift", "run", "--package-path", "Packages/FountainApps", "tools-factory-server"], cwd: repoPath, env: env)
    }
    func startFunctionCaller() {
        guard let repoPath else { errorMessage = "Select repository first"; return }
        var env = processEnv()
        env["FUNCTION_CALLER_BASE_URL"] = "http://127.0.0.1:8080/audiotalk/v1"
        runStreaming(command: ["swift", "run", "--package-path", "Packages/FountainApps", "function-caller-server"], cwd: repoPath, env: env)
    }
    func registerAudioTalkTools() {
        guard let repoPath else { errorMessage = "Select repository first"; return }
        var env = processEnv()
        env["TOOLS_FACTORY_URL"] = env["TOOLS_FACTORY_URL"] ?? "http://127.0.0.1:8011"
        env["TOOLS_CORPUS_ID"] = env["TOOLS_CORPUS_ID"] ?? "audiotalk"
        run(command: ["bash", "Scripts/register-audiotalk-tools.sh"], cwd: repoPath, env: env) { _, out in
            Task { @MainActor in self.logText += "\n[tools] \(out)\n" }
        }
    }

    func openDashboard() {
        NSWorkspace.shared.open(ctrlURL)
    }

    private func run(command: [String], cwd: String, env: [String: String]? = nil, completion: @Sendable @escaping (Int32, String) -> Void) {
        DispatchQueue.global().async {
            let proc = Process()
            proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = command
            if let env { proc.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new } }
            let pipe = Pipe(); proc.standardOutput = pipe; proc.standardError = pipe
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: data, encoding: .utf8) ?? ""
                completion(proc.terminationStatus, out)
            } catch {
                completion(1, String(describing: error))
            }
        }
    }

    func runStreaming(command: [String], cwd: String, env: [String: String]? = nil) {
        let proc = Process()
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = command
        if let env { proc.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new } }
        let pipe = Pipe(); proc.standardOutput = pipe; proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty { return }
            let chunk = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                var s = self.logText + chunk
                if s.count > 20000 { s = String(s.suffix(20000)) }
                self.logText = s
            }
        }
        try? proc.run()
    }

    // MARK: - PID helpers and logs
    private func pidURL(_ name: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".fountain", isDirectory: true)
            .appendingPathComponent("\(name).pid")
    }
    private func serviceLogURL(_ name: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".fountain", isDirectory: true)
            .appendingPathComponent("\(name).log")
    }
    private func readPID(_ name: String) -> String? {
        let url = pidURL(name)
        guard let data = try? Data(contentsOf: url), let s = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    func refreshAudioTalkPIDs() {
        audiotalkPID = readPID("audiotalk")
        functionCallerPID = readPID("function-caller")
        toolsFactoryPID = readPID("tools-factory")
    }
    func killAudioTalkAll() {
        let pids = [toolsFactoryPID, functionCallerPID, audiotalkPID].compactMap { $0 }
        guard !pids.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            func runKill(_ args: [String]) {
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/kill"); p.arguments = args
                try? p.run(); p.waitUntilExit()
            }
            for pid in pids { runKill(["-TERM", pid]); usleep(200_000); runKill(["-0", pid]); runKill(["-KILL", pid]) }
            Task { @MainActor in self.refreshAudioTalkPIDs() }
        }
    }
    func openAudioTalkLog(_ name: String) {
        let url = serviceLogURL(name)
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
    }
    func repoLogURL(_ name: String) -> URL? {
        guard let repo = repoPath else { return nil }
        return URL(fileURLWithPath: repo).appendingPathComponent(".fountain/logs/\(name).log")
    }
    func openRepoLog(_ name: String) {
        if let url = repoLogURL(name), FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
    }
    func fetchGatewayRoutes(_ completion: @Sendable @escaping (String) -> Void) {
        let defaultsURL = defaultsString("FountainAI.GATEWAY_URL", fallback: "http://127.0.0.1:8010")
        guard let base = URL(string: defaultsURL) else { completion("__INVALID_URL__"); return }
        var url = base; url.append(path: "/admin/routes")
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer = KeychainHelper.read(service: "FountainAI", account: "GATEWAY_BEARER"), !bearer.isEmpty {
            req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data else { completion(""); return }
            if let obj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
               let s = String(data: pretty, encoding: .utf8) {
                completion(s)
            } else if let s = String(data: data, encoding: .utf8) {
                completion(s)
            } else {
                completion("")
            }
        }.resume()
    }
    func defaultsString(_ key: String, fallback: String) -> String {
        let v = UserDefaults.standard.string(forKey: key) ?? ""
        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? fallback : t
    }
    func updateServiceLogs(maxChars: Int = 20_000) {
        func tail(_ url: URL) -> String {
            guard let data = try? Data(contentsOf: url), !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return "" }
            return s.count <= maxChars ? s : String(s.suffix(maxChars))
        }
        if runProfile == .fullStack, let repo = repoPath {
            let base = URL(fileURLWithPath: repo).appendingPathComponent(".fountain/logs")
            audiotalkLog = tail(serviceLogURL("audiotalk"))
            functionCallerLog = tail(base.appendingPathComponent("function-caller.log"))
            toolsFactoryLog = tail(base.appendingPathComponent("tools-factory.log"))
        } else {
            audiotalkLog = tail(serviceLogURL("audiotalk"))
            functionCallerLog = tail(serviceLogURL("function-caller"))
            toolsFactoryLog = tail(serviceLogURL("tools-factory"))
        }
    }

    // Build environment for child processes: secrets from Keychain, URLs from defaults
    func processEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Ensure signed binaries receive a valid launcher signature
        if env["LAUNCHER_SIGNATURE"] == nil {
            if let sig = KeychainHelper.read(service: "FountainAI", account: "LAUNCHER_SIGNATURE"), !sig.isEmpty {
                env["LAUNCHER_SIGNATURE"] = sig
            } else {
                env["LAUNCHER_SIGNATURE"] = "B86D7CEE-24C4-4C4C-A107-8D0542D1965B"
            }
        }
        if let url = UserDefaults.standard.string(forKey: "FountainAI.FOUNTAINSTORE_URL"), !url.isEmpty { env["FOUNTAINSTORE_URL"] = url }
        if env["OPENAI_API_KEY"] == nil, let openai = KeychainHelper.read(service: "FountainAI", account: "OPENAI_API_KEY") { env["OPENAI_API_KEY"] = openai }
        if env["FOUNTAINSTORE_API_KEY"] == nil, let storeKey = KeychainHelper.read(service: "FountainAI", account: "FOUNTAINSTORE_API_KEY") { env["FOUNTAINSTORE_API_KEY"] = storeKey }
        if let gateway = UserDefaults.standard.string(forKey: "FountainAI.GATEWAY_URL"), !gateway.isEmpty { env["FOUNTAIN_GATEWAY_URL"] = gateway }
        if env["GATEWAY_BEARER"] == nil, let gatewayToken = KeychainHelper.read(service: "FountainAI", account: "GATEWAY_BEARER"), !gatewayToken.isEmpty { env["GATEWAY_BEARER"] = gatewayToken }
        if let corpus = UserDefaults.standard.string(forKey: "FountainAI.ENGRAVER_CORPUS_ID"), !corpus.isEmpty {
            env["ENGRAVER_CORPUS_ID"] = corpus
        }
        if let collection = UserDefaults.standard.string(forKey: "FountainAI.ENGRAVER_COLLECTION"), !collection.isEmpty {
            env["ENGRAVER_COLLECTION"] = collection
        }
        if let models = UserDefaults.standard.string(forKey: "FountainAI.ENGRAVER_MODELS"), !models.isEmpty {
            env["ENGRAVER_MODELS"] = models
        }
        if let defaultModel = UserDefaults.standard.string(forKey: "FountainAI.ENGRAVER_DEFAULT_MODEL"), !defaultModel.isEmpty {
            env["ENGRAVER_DEFAULT_MODEL"] = defaultModel
        }
        if UserDefaults.standard.bool(forKey: "FountainAI.ENGRAVER_DEBUG") {
            env["ENGRAVER_DEBUG"] = "1"
        }
        if let repo = repoPath {
            env["FOUNTAINAI_ROOT"] = repo
            env["FOUNTAINAI_SERVICES_DIR"] = URL(fileURLWithPath: repo).appendingPathComponent("dist/bin").path
            if let scripts = LauncherResources.locateScriptsDirectory(repoRoot: repo, environment: env) {
                env[LauncherResources.scriptsOverrideKey] = scripts.path
            }
            if let specs = LauncherResources.locateSpecDirectory(repoRoot: repo, environment: env) {
                env[LauncherResources.specsOverrideKey] = specs.path
            }
        }
        return env
    }

    func precompile() {
        guard let repoPath else { errorMessage = "Select repository first"; return }
        let env = processEnv()
        guard let script = LauncherResources.launcherScriptURL(repoRoot: repoPath, environment: env) else {
            errorMessage = "Launcher script not found in Scripts/"
            return
        }
        runStreaming(command: ["bash", script.path, "precompile"], cwd: repoPath, env: env)
    }

    // MARK: - Environment Management
    @Published var openAIKeyInput: String = ""
    @Published var storeURLInput: String = UserDefaults.standard.string(forKey: "FountainAI.FOUNTAINSTORE_URL") ?? ""
    @Published var storeKeyInput: String = ""
    @Published var gatewayURLInput: String = UserDefaults.standard.string(forKey: "FountainAI.GATEWAY_URL") ?? ""
    @Published var gatewayTokenInput: String = ""
    @Published var engraverCorpusInput: String = UserDefaults.standard.string(forKey: "FountainAI.ENGRAVER_CORPUS_ID") ?? "engraver-space"
    @Published var engraverCollectionInput: String = UserDefaults.standard.string(forKey: "FountainAI.ENGRAVER_COLLECTION") ?? "chat-turns"
    @Published var engraverModelsInput: String = UserDefaults.standard.string(forKey: "FountainAI.ENGRAVER_MODELS") ?? "gpt-4o-mini,gpt-4o"
    @Published var engraverDefaultModelInput: String = UserDefaults.standard.string(forKey: "FountainAI.ENGRAVER_DEFAULT_MODEL") ?? "gpt-4o-mini"
    @Published var engraverDebugEnabled: Bool = UserDefaults.standard.bool(forKey: "FountainAI.ENGRAVER_DEBUG")
    func saveEnv() {
        if !openAIKeyInput.isEmpty { _ = KeychainHelper.save(service: "FountainAI", account: "OPENAI_API_KEY", secret: openAIKeyInput); openAIKeyInput = "" }
        if !storeKeyInput.isEmpty { _ = KeychainHelper.save(service: "FountainAI", account: "FOUNTAINSTORE_API_KEY", secret: storeKeyInput); storeKeyInput = "" }
        UserDefaults.standard.set(storeURLInput, forKey: "FountainAI.FOUNTAINSTORE_URL")
        if !gatewayTokenInput.isEmpty { _ = KeychainHelper.save(service: "FountainAI", account: "GATEWAY_BEARER", secret: gatewayTokenInput); gatewayTokenInput = "" }
        UserDefaults.standard.set(gatewayURLInput, forKey: "FountainAI.GATEWAY_URL")
        UserDefaults.standard.set(engraverCorpusInput, forKey: "FountainAI.ENGRAVER_CORPUS_ID")
        UserDefaults.standard.set(engraverCollectionInput, forKey: "FountainAI.ENGRAVER_COLLECTION")
        UserDefaults.standard.set(engraverModelsInput, forKey: "FountainAI.ENGRAVER_MODELS")
        UserDefaults.standard.set(engraverDefaultModelInput, forKey: "FountainAI.ENGRAVER_DEFAULT_MODEL")
        UserDefaults.standard.set(engraverDebugEnabled, forKey: "FountainAI.ENGRAVER_DEBUG")
    }
    func clearOpenAIKey() { _ = KeychainHelper.delete(service: "FountainAI", account: "OPENAI_API_KEY") }
    func clearStoreKey() { _ = KeychainHelper.delete(service: "FountainAI", account: "FOUNTAINSTORE_API_KEY") }
    func clearGatewayToken() { _ = KeychainHelper.delete(service: "FountainAI", account: "GATEWAY_BEARER") }
    func exportDotEnv() {
        guard let repoPath else { errorMessage = "Select repository first"; return }
        var lines: [String] = []
        if let v = UserDefaults.standard.string(forKey: "FountainAI.FOUNTAINSTORE_URL"), !v.isEmpty { lines.append("FOUNTAINSTORE_URL=\(v)") }
        if let v = KeychainHelper.read(service: "FountainAI", account: "OPENAI_API_KEY"), !v.isEmpty { lines.append("OPENAI_API_KEY=\(v)") }
        if let v = KeychainHelper.read(service: "FountainAI", account: "FOUNTAINSTORE_API_KEY"), !v.isEmpty { lines.append("FOUNTAINSTORE_API_KEY=\(v)") }
        if let v = UserDefaults.standard.string(forKey: "FountainAI.GATEWAY_URL"), !v.isEmpty { lines.append("FOUNTAIN_GATEWAY_URL=\(v)") }
        if let v = KeychainHelper.read(service: "FountainAI", account: "GATEWAY_BEARER"), !v.isEmpty { lines.append("GATEWAY_BEARER=\(v)") }
        if let v = UserDefaults.standard.string(forKey: "FountainAI.ENGRAVER_CORPUS_ID"), !v.isEmpty { lines.append("ENGRAVER_CORPUS_ID=\(v)") }
        if let v = UserDefaults.standard.string(forKey: "FountainAI.ENGRAVER_COLLECTION"), !v.isEmpty { lines.append("ENGRAVER_COLLECTION=\(v)") }
        if let v = UserDefaults.standard.string(forKey: "FountainAI.ENGRAVER_MODELS"), !v.isEmpty { lines.append("ENGRAVER_MODELS=\(v)") }
        if let v = UserDefaults.standard.string(forKey: "FountainAI.ENGRAVER_DEFAULT_MODEL"), !v.isEmpty { lines.append("ENGRAVER_DEFAULT_MODEL=\(v)") }
        lines.append("ENGRAVER_DEBUG=\(engraverDebugEnabled ? 1 : 0)")
        let content = lines.joined(separator: "\n") + "\n"
        let url = URL(fileURLWithPath: repoPath).appendingPathComponent(".env")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            presentAlert(title: ".env saved", message: url.path)
        } catch {
            presentAlert(title: "Failed to write .env", message: String(describing: error))
        }
    }
    #if canImport(EngraverStudio)
    func makeEngraverConfiguration() -> EngraverStudioConfiguration {
        var env = processEnv()
        if (env["ENGRAVER_CORPUS_ID"] ?? "").isEmpty {
            env["ENGRAVER_CORPUS_ID"] = "engraver-space"
        }
        if (env["ENGRAVER_COLLECTION"] ?? "").isEmpty {
            env["ENGRAVER_COLLECTION"] = "chat-turns"
        }
        if (env["ENGRAVER_MODELS"] ?? "").isEmpty {
            env["ENGRAVER_MODELS"] = "gpt-4o-mini,gpt-4o"
        }
        if (env["ENGRAVER_DEFAULT_MODEL"] ?? "").isEmpty {
            env["ENGRAVER_DEFAULT_MODEL"] = "gpt-4o-mini"
        }
        env["ENGRAVER_DEBUG"] = engraverDebugEnabled ? "1" : "0"
        return EngraverStudioConfiguration(environment: env)
    }
    #endif
    private func startStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                do {
                    let (data, resp) = try await URLSession.shared.data(from: self.ctrlURL)
                    let ok = (resp as? HTTPURLResponse)?.statusCode == 200
                    if ok {
                        if let decoded = try? JSONDecoder().decode([CPServiceStatus].self, from: data) {
                            await MainActor.run { self.services = decoded }
                        }
                    }
                    await MainActor.run { self.controlPlaneOK = ok }
                } catch {
                    await MainActor.run { self.controlPlaneOK = false; self.services = [] }
                }
                await MainActor.run { self.refreshAudioTalkPIDs(); self.updateServiceLogs() }
            }
        }
    }

    private func startTailingLogs(reset: Bool = false) {
        tailProc?.terminate(); tailProc = nil
        guard let repoPath else { return }
        let logURL = URL(fileURLWithPath: repoPath).appendingPathComponent("logs/launcher.out")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let proc = Process(); tailProc = proc
        proc.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["tail", "-n", "200", "-f", logURL.path]
        let pipe = Pipe(); proc.standardOutput = pipe; proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty { return }
            let chunk = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                var s = self.logText + chunk
                if s.count > 20000 { s = String(s.suffix(20000)) }
                self.logText = s
            }
        }
        try? proc.run()
    }

    private func presentAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    func presentDebugInfo() {
        let id = Bundle.main.bundleIdentifier ?? "(nil)"
        let ver = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "(nil)"
        let name = (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "(nil)"
        let path = Bundle.main.bundleURL.path
        let exec = Bundle.main.executableURL?.path ?? "(nil)"
        presentAlert(title: "Debug Info", message: "BundleID: \(id)\nName: \(name)\nVersion: \(ver)\nBundle: \(path)\nExecutable: \(exec)")
    }
}

struct ContentView: View {
    @ObservedObject var vm: LauncherViewModel
    private var minWidth: CGFloat { (vm.tab == .engraver || vm.tab == .audiotalk) ? 960 : 760 }
    private var minHeight: CGFloat { (vm.tab == .engraver || vm.tab == .audiotalk) ? 620 : 480 }
    var body: some View {
        TabView(selection: $vm.tab) {
            ControlTab(vm: vm)
                .tabItem { Label("Control", systemImage: "switch.2") }
                .tag(LauncherViewModel.Tab.control)
            if #available(macOS 13.0, *) {
                #if canImport(EngraverStudio)
                EngraverTab(vm: vm)
                    .tabItem { Label("Engraver", systemImage: "wand.and.stars") }
                    .tag(LauncherViewModel.Tab.engraver)
                #endif
                AudioTalkTab(vm: vm)
                    .tabItem { Label("AudioTalk", systemImage: "music.quarternote.3") }
                    .tag(LauncherViewModel.Tab.audiotalk)
            }
        }
        .frame(minWidth: minWidth, minHeight: minHeight)
    }
}

struct Msg: Identifiable { let id = UUID(); let text: String }

// MARK: - Tabs
struct ControlTab: View {
    @ObservedObject var vm: LauncherViewModel
    @State private var leftWidth: CGFloat = 320
    @State private var rightWidth: CGFloat = 360
    private var buildVersion: String { (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "dev" }
    @State private var copied: Bool = false
    var body: some View {
        HSplitView {
            // Left: Principal
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Fountain Launcher • build \(buildVersion)").font(.headline)
                    Spacer()
                    Button("Debug Info") { vm.presentDebugInfo() }
                }
                HStack(spacing: 8) {
                    Circle().fill(vm.controlPlaneOK ? Color.green : Color.red).frame(width: 10, height: 10)
                        .animation(.easeInOut(duration: 0.18), value: vm.controlPlaneOK)
                    Text(vm.controlPlaneOK ? "Reachable" : (vm.starting ? "Booting…" : "Not reachable")).font(.callout)
                    Spacer()
                }
                if let repo = vm.repoPath {
                    Text("Repo: \(repo)").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Button("Choose Repo…") { vm.chooseRepo() }
                }
                Picker("Build", selection: Binding(get: { vm.buildMode }, set: { vm.buildMode = $0 })) {
                    Text("Auto").tag(LauncherViewModel.BuildMode.auto)
                    Text("No Build").tag(LauncherViewModel.BuildMode.noBuild)
                    Text("Force").tag(LauncherViewModel.BuildMode.forceBuild)
                }.pickerStyle(.segmented)
                HStack(spacing: 8) {
                    Button("Start") { vm.start() }.disabled(vm.repoPath == nil || vm.starting)
                    Button("Stop") { vm.stop() }
                    Button("Diagnostics") { vm.diagnostics() }
                    Spacer()
                    Button("Precompile") { vm.precompile() }
                }
                GroupBox(label: Text("AudioTalk")) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Text("Ports:").font(.caption)
                            Text("AT: \(vm.audioTalkPort)")
                            Text("FC: \(vm.functionCallerPort)")
                            Text("TF: \(vm.toolsFactoryPort)")
                            Spacer()
                        }
                        HStack(spacing: 10) {
                            Text("PIDs:").font(.caption)
                            Text("AT=") + Text(vm.audiotalkPID ?? "–").foregroundColor(.secondary)
                            Text("FC=") + Text(vm.functionCallerPID ?? "–").foregroundColor(.secondary)
                            Text("TF=") + Text(vm.toolsFactoryPID ?? "–").foregroundColor(.secondary)
                            Spacer()
                            Button("Start") { vm.startAudioTalkStack() }
                            Button("Stop") { vm.stopAudioTalkStack() }
                            Button("Kill") { vm.killAudioTalkAll() }
                        }.font(.caption)
                    }
                }
                DisclosureGroup("Environment") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { SecureField("OPENAI_API_KEY", text: $vm.openAIKeyInput); Button("Clear") { vm.clearOpenAIKey() } }
                        HStack { TextField("FOUNTAINSTORE_URL", text: $vm.storeURLInput) }
                        HStack { SecureField("FOUNTAINSTORE_API_KEY", text: $vm.storeKeyInput); Button("Clear") { vm.clearStoreKey() } }
                        HStack { TextField("FOUNTAIN_GATEWAY_URL", text: $vm.gatewayURLInput) }
                        HStack { SecureField("GATEWAY_BEARER", text: $vm.gatewayTokenInput); Button("Clear") { vm.clearGatewayToken() } }
                        Divider()
                        HStack { TextField("ENGRAVER_CORPUS_ID", text: $vm.engraverCorpusInput) }
                        HStack { TextField("ENGRAVER_COLLECTION", text: $vm.engraverCollectionInput) }
                        HStack { TextField("ENGRAVER_MODELS (comma separated)", text: $vm.engraverModelsInput) }
                        HStack { TextField("ENGRAVER_DEFAULT_MODEL", text: $vm.engraverDefaultModelInput) }
                        Toggle("Diagnostics (ENGRAVER_DEBUG)", isOn: $vm.engraverDebugEnabled).toggleStyle(.switch)
                        HStack { Button("Save Env") { vm.saveEnv() }; Button("Export .env") { vm.exportDotEnv() } }
                    }
                }
                Spacer()
            }
            .padding(16)
            .frame(minWidth: 260, idealWidth: leftWidth)

            // Middle: Editing / Logs
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Logs").font(.headline)
                    Spacer()
                    Toggle("Follow", isOn: $vm.followTailMain).toggleStyle(.switch).labelsHidden()
                    Button("Copy") {
                        NSPasteboard.general.clearContents();
                        NSPasteboard.general.setString(vm.logText, forType: .string)
                        copied = true
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            copied = false
                        }
                    }
                }
                LogTailView(text: vm.logText, follow: vm.followTailMain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(16)
            .frame(minWidth: 420)

            // Right: Optional / Service diagnostics + Specs
            VStack(alignment: .leading, spacing: 12) {
                // OpenAPI integrated with diagnostics
                OpenAPISidePanel(vm: vm)
                GroupBox(label: Text("Service Logs")) {
                    VStack(alignment: .leading, spacing: 8) {
                        DisclosureGroup(isExpanded: Binding(get: { vm.showAudioTalkLog }, set: { vm.showAudioTalkLog = $0 })) {
                            TextEditor(text: Binding(get: { vm.audiotalkLog }, set: { _ in }))
                                .font(.system(.footnote, design: .monospaced))
                                .frame(minHeight: 120)
                        } label: { Text("AudioTalk") }
                        DisclosureGroup(isExpanded: Binding(get: { vm.showFunctionCallerLog }, set: { vm.showFunctionCallerLog = $0 })) {
                            TextEditor(text: Binding(get: { vm.functionCallerLog }, set: { _ in }))
                                .font(.system(.footnote, design: .monospaced))
                                .frame(minHeight: 120)
                        } label: { Text("Function Caller") }
                        DisclosureGroup(isExpanded: Binding(get: { vm.showToolsFactoryLog }, set: { vm.showToolsFactoryLog = $0 })) {
                            TextEditor(text: Binding(get: { vm.toolsFactoryLog }, set: { _ in }))
                                .font(.system(.footnote, design: .monospaced))
                                .frame(minHeight: 120)
                        } label: { Text("Tools Factory") }
                    }
                }
                GroupBox(label: Text("Services")) {
                    if vm.controlPlaneOK && !vm.services.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(vm.services, id: \.name) { s in
                                HStack {
                                    Circle().fill(s.healthy ? Color.green : (s.running ? Color.yellow : Color.gray)).frame(width: 8, height: 8)
                                    Text(s.name)
                                    Spacer()
                                    Button("View Log") { vm.openServiceLog(name: s.name) }
                                }
                            }
                        }
                    } else {
                        Text(vm.starting ? "Waiting for services…" : "No services yet.").foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(16)
            .frame(minWidth: 280, idealWidth: rightWidth)
        }
        .animation(.easeInOut(duration: 0.2), value: vm.controlPlaneOK)
        .overlay(alignment: .topTrailing) {
            if copied { Text("Copied").padding(6).background(Color.black.opacity(0.7)).foregroundColor(.white).cornerRadius(6).padding() }
        }
    }
}

struct EnvTab: View {
    @ObservedObject var vm: LauncherViewModel
    @State private var copied: Bool = false
    var body: some View {
        ThreePane(leftWidth: 320, rightWidth: 340) {
            // Left: principal (edit)
            VStack(alignment: .leading, spacing: 10) {
                HStack { Button("Back to Control") { vm.tab = .control }; Spacer() }
                GroupBox(label: Text("Environment")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { SecureField("OPENAI_API_KEY", text: $vm.openAIKeyInput); Button("Clear") { vm.clearOpenAIKey() } }
                        HStack { TextField("FOUNTAINSTORE_URL", text: $vm.storeURLInput) }
                        HStack { SecureField("FOUNTAINSTORE_API_KEY", text: $vm.storeKeyInput); Button("Clear") { vm.clearStoreKey() } }
                        Divider()
                        HStack { TextField("FOUNTAIN_GATEWAY_URL", text: $vm.gatewayURLInput) }
                        HStack { SecureField("GATEWAY_BEARER", text: $vm.gatewayTokenInput); Button("Clear") { vm.clearGatewayToken() } }
                        Divider()
                        HStack { TextField("ENGRAVER_CORPUS_ID", text: $vm.engraverCorpusInput) }
                        HStack { TextField("ENGRAVER_COLLECTION", text: $vm.engraverCollectionInput) }
                        HStack { TextField("ENGRAVER_MODELS (comma separated)", text: $vm.engraverModelsInput) }
                        HStack { TextField("ENGRAVER_DEFAULT_MODEL", text: $vm.engraverDefaultModelInput) }
                        Toggle("Enable Diagnostics (ENGRAVER_DEBUG)", isOn: $vm.engraverDebugEnabled)
                            .toggleStyle(.switch)
                        HStack {
                            Button("Save Env") { vm.saveEnv() }
                            Button("Export .env (0600)") { vm.exportDotEnv() }
                            Spacer()
                        }
                    }
                }
                Spacer()
            }
            .padding(16)
        } middle: {
            // Middle: detail (sanitized report)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sanitized Report").font(.headline)
                    Spacer()
                    Button("Copy") {
                        let text = vm.sanitizedEnvReport()
                        NSPasteboard.general.clearContents();
                        NSPasteboard.general.setString(text, forType: .string)
                        copied = true
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            copied = false
                        }
                    }
                }
                ScrollView {
                    Text(vm.sanitizedEnvReport())
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
            .padding(16)
        } right: {
            // Right: optional (tips)
            VStack(alignment: .leading, spacing: 12) {
                GroupBox(label: Text("Tips")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Secrets are stored in macOS Keychain under service ‘FountainAI’. Use the AudioTalk menu or Control pane for stack actions.")
                            .font(.caption)
                        Text("Use Copy to export a sanitized report for support without leaking secrets.")
                            .font(.caption)
                    }
                }
                Spacer()
            }
            .padding(16)
        }
        .overlay(alignment: .topTrailing) {
            if copied { Text("Copied").padding(6).background(Color.black.opacity(0.7)).foregroundColor(.white).cornerRadius(6).padding() }
        }
    }
}

#if canImport(EngraverStudio)
struct EngraverTab: View {
    @ObservedObject var vm: LauncherViewModel

    var body: some View {
        if #available(macOS 13.0, *) {
            let config = vm.makeEngraverConfiguration()
            EngraverStudioRoot(configuration: config)
                .id(configIdentity(config))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("Engraver Studio requires macOS 13 or newer.")
                    .font(.headline)
                Text("Upgrade the operating system to interact with the live token stream UI.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(24)
        }
    }

    @available(macOS 13.0, *)
    private func configIdentity(_ config: EngraverStudioConfiguration) -> String {
        let models = config.availableModels.joined(separator: ",")
        let prompts = config.systemPrompts.joined(separator: "|")
        let persistenceKey = config.persistenceStore == nil ? "transient" : "persisted"
        let tokenFlag = config.bearerToken == nil ? "token:none" : "token:set"
        return [
            config.gatewayURL.absoluteString,
            config.corpusId,
            config.collection,
            models,
            config.defaultModel,
            persistenceKey,
            tokenFlag,
            prompts
        ].joined(separator: "#")
    }
}
#endif

struct AudioTalkTab: View {
    @ObservedObject var vm: LauncherViewModel
    @State private var screenplayId: String = ""
    @State private var notationId: String = ""
    var body: some View {
        ThreePane(leftWidth: 280, rightWidth: 320) {
            // Left: principal
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text("AudioTalk Studio").font(.headline)
                        Circle()
                            .fill(vm.controlPlaneOK ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.18), value: vm.controlPlaneOK)
                        Spacer()
                    }
                    Text("Use the AudioTalk menu for actions").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Session").font(.subheadline)
                    Text("Screenplay ID").font(.caption)
                    TextField("screenplay-id", text: $screenplayId).textFieldStyle(.roundedBorder)
                    Text("Notation Session ID").font(.caption)
                    TextField("notation-id", text: $notationId).textFieldStyle(.roundedBorder)
                    Text("Use CLI or ToolsFactory to PUT source, parse, map cues, and apply.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                    Text("Runtime").font(.subheadline)
                    HStack(spacing: 10) {
                        Text("AT:") + Text("\(vm.audioTalkPort)")
                        Text("FC:") + Text("\(vm.functionCallerPort)")
                        Text("TF:") + Text("\(vm.toolsFactoryPort)")
                    }.font(.caption)
                    HStack(spacing: 10) {
                        Text("AT PID=") + Text(vm.audiotalkPID ?? "–").foregroundStyle(.secondary)
                        Text("FC PID=") + Text(vm.functionCallerPID ?? "–").foregroundStyle(.secondary)
                        Text("TF PID=") + Text(vm.toolsFactoryPID ?? "–").foregroundStyle(.secondary)
                    }.font(.caption)
                }
                .padding(16)
            }
        } middle: {
            // Middle: utmost detail editing
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Fountain Editor (connect later)").font(.caption)
                    Rectangle()
                        .fill(Color.gray.opacity(0.07))
                        .frame(height: 260)
                        .overlay(Text("Fountain text here").foregroundStyle(.secondary))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    Text("Lily Editor + Preview (connect later)").font(.caption)
                    Rectangle()
                        .fill(Color.gray.opacity(0.07))
                        .frame(height: 260)
                        .overlay(Text("Lily source / preview here").foregroundStyle(.secondary))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                }
                .padding(16)
            }
        } right: {
            // Right: optionals
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox(label: Text("Quick Links")) {
                        VStack(alignment: .leading, spacing: 6) {
                            Button("Open AudioTalk Log") { vm.openAudioTalkLog("audiotalk") }
                            Button("Open FunctionCaller Log") { vm.openAudioTalkLog("function-caller") }
                            Button("Open ToolsFactory Log") { vm.openAudioTalkLog("tools-factory") }
                        }.font(.caption)
                    }
                    GroupBox(label: Text("Tips")) {
                        Text("Use Cmd+Shift+S/X/K/P for Start/Stop/Kill/Precompile").font(.caption)
                        Text("Stack ports and PIDs update live.").font(.caption)
                    }
                    Spacer()
                }
                .padding(16)
            }
        }
    }
}

// MARK: - Models & Actions
struct CPServiceStatus: Codable, Hashable { let name: String; let running: Bool; let healthy: Bool }

extension LauncherViewModel {
    func sanitizedEnvReport() -> String {
        let hasOA = KeychainHelper.read(service: "FountainAI", account: "OPENAI_API_KEY") != nil
        let hasFS = KeychainHelper.read(service: "FountainAI", account: "FOUNTAINSTORE_API_KEY") != nil
        let url = UserDefaults.standard.string(forKey: "FountainAI.FOUNTAINSTORE_URL") ?? ""
        let gatewayURL = UserDefaults.standard.string(forKey: "FountainAI.GATEWAY_URL") ?? ""
        let hasGateway = KeychainHelper.read(service: "FountainAI", account: "GATEWAY_BEARER") != nil
        let engraverCorpus = UserDefaults.standard.string(forKey: "FountainAI.ENGRAVER_CORPUS_ID") ?? ""
        let engraverCollection = UserDefaults.standard.string(forKey: "FountainAI.ENGRAVER_COLLECTION") ?? ""
        let engraverModels = UserDefaults.standard.string(forKey: "FountainAI.ENGRAVER_MODELS") ?? ""
        let engraverDefault = UserDefaults.standard.string(forKey: "FountainAI.ENGRAVER_DEFAULT_MODEL") ?? ""
        let engraverDebug = UserDefaults.standard.bool(forKey: "FountainAI.ENGRAVER_DEBUG")
        return """
Env Report
OPENAI_API_KEY=\(hasOA ? "***" : "(missing)")
FOUNTAINSTORE_URL=\(url.isEmpty ? "(missing)" : url)
FOUNTAINSTORE_API_KEY=\(hasFS ? "***" : "(missing)")
FOUNTAIN_GATEWAY_URL=\(gatewayURL.isEmpty ? "(missing)" : gatewayURL)
GATEWAY_BEARER=\(hasGateway ? "***" : "(missing)")
ENGRAVER_CORPUS_ID=\(engraverCorpus.isEmpty ? "(missing)" : engraverCorpus)
ENGRAVER_COLLECTION=\(engraverCollection.isEmpty ? "(missing)" : engraverCollection)
ENGRAVER_MODELS=\(engraverModels.isEmpty ? "(missing)" : engraverModels)
ENGRAVER_DEFAULT_MODEL=\(engraverDefault.isEmpty ? "(missing)" : engraverDefault)
ENGRAVER_DEBUG=\(engraverDebug ? "enabled" : "disabled")
"""
    }
    enum ServiceAction { case start, stop, restart }
    func serviceAction(name: String, action: ServiceAction) {
        guard controlPlaneOK else { return }
        let path: String
        switch action { case .start: path = "/start/"+name; case .stop: path = "/stop/"+name; case .restart: path = "/restart/"+name }
        var req = URLRequest(url: URL(string: "http://127.0.0.1:9090\(path)")!)
        req.httpMethod = "POST"
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }

    func openServiceLog(name: String) {
        guard let repo = repoPath else { return }
        let sanitized = name.replacingOccurrences(of: " ", with: "_")
        let url = URL(fileURLWithPath: repo).appendingPathComponent("logs/\(sanitized).log")
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            presentAlert(title: "No log yet", message: url.path)
        }
    }
}
#endif
#if !(canImport(SwiftUI) && canImport(AppKit))
@main
enum FountainLauncherUIUnavailable {
    static func main() {
        let message = "FountainLauncherUI is only supported on macOS.\n"
        if let data = message.data(using: .utf8) {
            try? FileHandle.standardError.write(contentsOf: data)
        }
    }
}
#endif
