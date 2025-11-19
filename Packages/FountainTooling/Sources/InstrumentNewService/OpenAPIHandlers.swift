import Foundation
import OpenAPIRuntime
import InstrumentNewCore

/// OpenAPI-generated server implementation for the Instrument New service.
public struct InstrumentNewOpenAPI: APIProtocol, @unchecked Sendable {
    public init() {}

    public func runInstrumentNew(_ input: Operations.runInstrumentNew.Input) async throws -> Operations.runInstrumentNew.Output {
        guard case let .json(req) = input.body else {
            let fallback = Components.Schemas.InstrumentNewResponse(
                ok: false,
                appId: "",
                agentId: "",
                specName: "",
                applied: [],
                warnings: ["instrument-new: expected JSON request body"],
                dryRun: true
            )
            return .ok(.init(body: .json(fallback)))
        }

        let cfg = InstrumentNew.Config(
            appId: req.appId,
            agentId: req.agentId,
            specName: req.specName,
            visual: req.visual ?? true,
            metalView: req.metalview ?? false,
            noApp: req.noApp ?? false
        )

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

        var applied: [String] = [
            "spec",
            "facts-mapping",
            "instrument-index",
            "seeder",
            "tests"
        ]
        if cfg.visual && !cfg.noApp {
            applied.append("app")
        }

        let dryRun = req.dryRun ?? false
        var ok = true
        var warnings: [String] = []

        do {
            try InstrumentNew.generate(in: root, config: cfg, dryRun: dryRun)
        } catch {
            ok = false
            warnings.append(error.localizedDescription)
        }

        let response = Components.Schemas.InstrumentNewResponse(
            ok: ok,
            appId: cfg.appId,
            agentId: cfg.agentId,
            specName: cfg.specName,
            applied: applied,
            warnings: warnings.isEmpty ? nil : warnings,
            dryRun: dryRun
        )
        return .ok(.init(body: .json(response)))
    }
}

