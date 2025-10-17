import Foundation
import Combine
import FountainAIKit

public final class EnvironmentControllerAdapter: EnvironmentController {
    private let manager: FountainEnvironmentManager

    public init(fountainRepoRoot: URL?) {
        self.manager = FountainEnvironmentManager(fountainRepoRoot: fountainRepoRoot)
    }

    public var overallState: EnvironmentOverallState { manager.overallState }
    public var services: [EnvironmentServiceStatus] { manager.services }
    public var logs: [EnvironmentLogEntry] { manager.logs }

    public func observeOverallState(_ onChange: @escaping (EnvironmentOverallState) -> Void) -> AnyCancellable {
        manager.$overallState.sink(receiveValue: onChange)
    }
    public func observeServices(_ onChange: @escaping ([EnvironmentServiceStatus]) -> Void) -> AnyCancellable {
        manager.$services.sink(receiveValue: onChange)
    }
    public func observeLogs(_ onChange: @escaping ([EnvironmentLogEntry]) -> Void) -> AnyCancellable {
        manager.$logs.sink(receiveValue: onChange)
    }

    public func refreshStatus() async { await manager.refreshStatus() }
    public func startEnvironment(includeExtras: Bool) async { await manager.startEnvironment(includeExtras: includeExtras) }
    public func stopEnvironment(includeExtras: Bool, force: Bool) async { await manager.stopEnvironment(includeExtras: includeExtras, force: force) }
    public func clearLogs() { manager.clearLogs() }
    public func forceKillPID(_ pid: String) async { await manager.forceKillPID(pid) }
    public func restartService(_ service: EnvironmentServiceStatus) async { await manager.restartService(service) }
    public func fixAll() async { await manager.fixAll() }
}

