import Foundation

public enum EnvironmentOverallState: Equatable, Sendable {
    case unavailable(String)
    case idle
    case checking
    case starting
    case stopping
    case running
    case failed(String)
}

public enum EnvironmentServiceState: String, Equatable, Sendable {
    case up
    case down
    case unknown
}

public struct EnvironmentServiceStatus: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let port: Int
    public let state: EnvironmentServiceState
    public let pid: String?

    public init(name: String, port: Int, state: EnvironmentServiceState, pid: String?) {
        self.id = name
        self.name = name
        self.port = port
        self.state = state
        self.pid = pid
    }
}

public struct EnvironmentLogEntry: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let line: String

    public init(timestamp: Date = Date(), line: String) {
        self.timestamp = timestamp
        self.line = line
    }
}

