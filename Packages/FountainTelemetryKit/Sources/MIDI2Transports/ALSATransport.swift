import Foundation

public final class ALSATransport: MIDITransport {
    public var onReceiveUMP: (([UInt32]) -> Void)?
    private let loopback: LoopbackTransport?

    /// Create a transport.
    /// - Parameter useLoopback: when true, the transport echoes data back using a `LoopbackTransport`.
    public init(useLoopback: Bool = false) {
        if useLoopback {
            let lb = LoopbackTransport()
            self.loopback = lb
        } else {
            self.loopback = nil
        }
    }

    public func open() throws {
        if let lb = loopback {
            lb.onReceiveUMP = { [weak self] words in
                self?.onReceiveUMP?(words)
            }
            try lb.open()
        }
    }

    public func close() throws {
        try loopback?.close()
    }

    public func send(umpWords: [UInt32]) throws {
        if let lb = loopback {
            try lb.send(umpWords: umpWords)
        } else {
            // Fallback: directly deliver to receiver.
            onReceiveUMP?(umpWords)
        }
    }

    /// Parse ALSA sequencer clients from `/proc`.
    /// - Parameter path: optional override for test fixtures.
    /// - Returns: array of client names.
    public static func availableEndpoints(from path: String = "/proc/asound/seq/clients") -> [String] {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("client"),
                  let nameStart = line.firstIndex(of: "'"),
                  let nameEnd = line.lastIndex(of: "'") else { return nil }
            return String(line[line.index(after: nameStart)..<nameEnd])
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
