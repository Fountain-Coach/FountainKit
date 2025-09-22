import Foundation

public final class Metrics {
    private let lock = NSLock()
    private var sendBytesTotal: UInt64 = 0
    private var recvBytesTotal: UInt64 = 0
    private var acksSent: UInt64 = 0
    private var nacksSent: UInt64 = 0
    private var retransmits: UInt64 = 0
    private var seqGapsDetected: UInt64 = 0

    public init() {}

    public func addSend(bytes: Int) {
        lock.with { sendBytesTotal &+= UInt64(bytes) }
    }

    public func addRecv(bytes: Int) {
        lock.with { recvBytesTotal &+= UInt64(bytes) }
    }

    public func incAcksSent() {
        lock.with { acksSent &+= 1 }
    }

    public func incNacksSent() {
        lock.with { nacksSent &+= 1 }
    }

    public func incRetransmits(_ n: Int) {
        lock.with { retransmits &+= UInt64(n) }
    }

    public func incSeqGapsDetected() {
        lock.with { seqGapsDetected &+= 1 }
    }

    public struct Snapshot {
        public let sendBytesTotal: UInt64
        public let recvBytesTotal: UInt64
        public let acksSent: UInt64
        public let nacksSent: UInt64
        public let retransmits: UInt64
        public let seqGapsDetected: UInt64
    }

    public func snapshot() -> Snapshot {
        lock.with {
            Snapshot(
                sendBytesTotal: sendBytesTotal,
                recvBytesTotal: recvBytesTotal,
                acksSent: acksSent,
                nacksSent: nacksSent,
                retransmits: retransmits,
                seqGapsDetected: seqGapsDetected
            )
        }
    }
}

private extension NSLock {
    func with<T>(_ body: () -> T) -> T {
        self.lock()
        defer { self.unlock() }
        return body()
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
