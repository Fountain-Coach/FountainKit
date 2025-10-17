import Foundation
import Combine

public protocol EnvironmentController: AnyObject, Sendable {
    // Snapshot accessors
    var overallState: EnvironmentOverallState { get }
    var services: [EnvironmentServiceStatus] { get }
    var logs: [EnvironmentLogEntry] { get }

    // Observers
    func observeOverallState(_ onChange: @escaping (EnvironmentOverallState) -> Void) -> AnyCancellable
    func observeServices(_ onChange: @escaping ([EnvironmentServiceStatus]) -> Void) -> AnyCancellable
    func observeLogs(_ onChange: @escaping ([EnvironmentLogEntry]) -> Void) -> AnyCancellable

    // Controls
    func refreshStatus() async
    func startEnvironment(includeExtras: Bool) async
    func stopEnvironment(includeExtras: Bool, force: Bool) async
    func clearLogs()
    func forceKillPID(_ pid: String) async
    func restartService(_ service: EnvironmentServiceStatus) async
    func fixAll() async
}

