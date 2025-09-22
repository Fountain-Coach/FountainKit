import NIOCore
import Logging
import NIOConcurrencyHelpers
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Minimal DNS engine capable of parsing A, AAAA and CNAME record queries and responding from an in-memory zone cache.
public struct DNSEngine: Sendable {
    public struct Record: Sendable {
        public let name: String
        public let type: String
        public let value: String
        public init(name: String, type: String, value: String) {
            self.name = name
            self.type = type
            self.value = value
        }
    }

    struct Key: Hashable {
        let name: String
        let type: String
    }

    /// Thread-safe mapping of fully qualified domain names and types to records.
    private let zoneCache: NIOLockedValueBox<[Key: Record]>
    private let logger = Logger(label: "DNSEngine")
    /// Optional DNSSEC signer used for zone signing and verification.
    private let signer: DNSSECSigner?

    /// Creates a new engine with the provided records.
    /// - Parameters:
    ///   - records: Array of ``Record`` entries.
    ///   - signer: Optional ``DNSSECSigner`` for zone signing.
    public init(records: [Record], signer: DNSSECSigner? = nil) {
        var map: [Key: Record] = [:]
        for record in records {
            map[Key(name: record.name, type: record.type)] = record
        }
        self.zoneCache = NIOLockedValueBox(map)
        self.signer = signer
    }

    /// Convenience initializer for legacy IPv4 caches.
    public init(zoneCache: [String: String], signer: DNSSECSigner? = nil) {
        let records = zoneCache.map { Record(name: $0.key, type: "A", value: $0.value) }
        self.init(records: records, signer: signer)
    }

    /// Creates a new engine from a ``ZoneManager`` instance.
    /// - Parameters:
    ///   - zoneManager: Zone manager providing records.
    ///   - signer: Optional ``DNSSECSigner`` for zone signing.
    @MainActor
    public init(zoneManager: ZoneManager, signer: DNSSECSigner? = nil) async {
        let records = await zoneManager.allRecords()
        var cache: [Key: Record] = [:]
        for (key, record) in records {
            cache[Key(name: key.name, type: key.type)] = Record(name: key.name, type: record.type, value: record.value)
        }
        self.zoneCache = NIOLockedValueBox(cache)
        self.signer = signer
        let cacheBox = self.zoneCache
        Task {
            for await records in zoneManager.updates {
                cacheBox.withLockedValue { cache in
                    cache.removeAll()
                    for (key, record) in records {
                        cache[Key(name: key.name, type: key.type)] = Record(name: key.name, type: record.type, value: record.value)
                    }
                }
            }
        }
    }

    /// Updates or inserts a record in the zone cache.
    public func updateRecord(name: String, type: String, value: String) {
        zoneCache.withLockedValue { $0[Key(name: name, type: type)] = Record(name: name, type: type, value: value) }
    }

    /// Generates a signature for the current zone if a signer is configured.
    /// - Returns: Signature bytes or `nil` when no signer is set.
    public func signZone() throws -> Data? {
        guard let signer else { return nil }
        let zone = zoneCache.withLockedValue { cache in
            cache.map { "\($0.key.name) \($0.key.type) \($0.value.value)" }.sorted().joined(separator: "\n")
        }
        return try signer.sign(zone: zone)
    }

    /// Verifies the provided signature against the current zone state.
    /// - Parameter signature: Signature bytes to verify.
    /// - Returns: `nil` if no signer is configured, otherwise the verification result.
    public func verifyZone(signature: Data) -> Bool? {
        guard let signer else { return nil }
        let zone = zoneCache.withLockedValue { cache in
            cache.map { "\($0.key.name) \($0.key.type) \($0.value.value)" }.sorted().joined(separator: "\n")
        }
        return signer.verify(zone: zone, signature: signature)
    }

    /// Parses an incoming DNS query and constructs a response if the record exists in the cache.
    /// - Parameter buffer: Byte buffer containing the DNS query.
    /// - Returns: A byte buffer with the DNS response or `nil` if the record is unknown or parsing fails.
    public func handleQuery(buffer: inout ByteBuffer) -> ByteBuffer? {
        guard let parser = DNSParser(buffer: &buffer) else {
            logger.warning("Failed to parse query")
            Task { await DNSMetrics.shared.record(query: "invalid", type: "invalid", hit: false) }
            return nil
        }
        let response = zoneCache.withLockedValue { cache -> ByteBuffer? in
            guard let record = cache[Key(name: parser.name, type: parser.typeName)] else { return nil }
            return parser.makeResponse(record: record)
        }
        Task { await DNSMetrics.shared.record(query: parser.name, type: parser.typeName, hit: response != nil) }
        logger.info("dns_query", metadata: ["name": .string(parser.name), "type": .string(parser.typeName), "hit": .string(String(response != nil))])
        return response
    }
}

/// Simple DNS message parser for queries and responses.
struct DNSParser {
    let id: UInt16
    let name: String
    let qtype: UInt16

    init?(buffer: inout ByteBuffer) {
        guard buffer.readableBytes >= 12,
              let id = buffer.readInteger(as: UInt16.self) else { return nil }
        self.id = id
        // Skip flags and counts
        buffer.moveReaderIndex(forwardBy: 10)
        var labels: [String] = []
        while let length: UInt8 = buffer.readInteger(as: UInt8.self), length > 0 {
            guard let bytes = buffer.readBytes(length: Int(length)),
                  let label = String(bytes: bytes, encoding: .utf8) else {
                return nil
            }
            labels.append(label)
        }
        guard let qtype: UInt16 = buffer.readInteger(as: UInt16.self),
              buffer.readInteger(as: UInt16.self) != nil else { return nil }
        self.qtype = qtype
        self.name = labels.joined(separator: ".")
    }

    var typeName: String {
        switch qtype {
        case 1: return "A"
        case 5: return "CNAME"
        case 28: return "AAAA"
        default: return "UNKNOWN"
        }
    }

    func makeResponse(record: DNSEngine.Record) -> ByteBuffer? {
        var buf = ByteBufferAllocator().buffer(capacity: 512)
        buf.writeInteger(id, as: UInt16.self)
        buf.writeInteger(UInt16(0x8180), as: UInt16.self) // standard response
        buf.writeInteger(UInt16(1), as: UInt16.self) // QDCOUNT
        buf.writeInteger(UInt16(1), as: UInt16.self) // ANCOUNT
        buf.writeInteger(UInt16(0), as: UInt16.self) // NSCOUNT
        buf.writeInteger(UInt16(0), as: UInt16.self) // ARCOUNT

        // question section
        for label in name.split(separator: ".") {
            let bytes = Array(label.utf8)
            buf.writeInteger(UInt8(bytes.count), as: UInt8.self)
            buf.writeBytes(bytes)
        }
        buf.writeInteger(UInt8(0), as: UInt8.self)
        buf.writeInteger(qtype, as: UInt16.self)
        buf.writeInteger(UInt16(1), as: UInt16.self) // QCLASS IN

        // answer section
        buf.writeInteger(UInt16(0xC00C), as: UInt16.self) // pointer to name at offset 12
        let typeCode = qtype
        buf.writeInteger(typeCode, as: UInt16.self)
        buf.writeInteger(UInt16(1), as: UInt16.self) // CLASS IN
        buf.writeInteger(UInt32(300), as: UInt32.self) // TTL

        switch record.type {
        case "A":
            let octets = record.value.split(separator: ".").compactMap { UInt8($0) }
            guard octets.count == 4 else { return nil }
            buf.writeInteger(UInt16(4), as: UInt16.self)
            buf.writeBytes(octets)
        case "AAAA":
            var addr = in6_addr()
            let res = record.value.withCString { inet_pton(AF_INET6, $0, &addr) }
            guard res == 1 else { return nil }
            let bytes = withUnsafeBytes(of: &addr) { Array($0) }
            buf.writeInteger(UInt16(bytes.count), as: UInt16.self)
            buf.writeBytes(bytes)
        case "CNAME":
            var rdata = ByteBufferAllocator().buffer(capacity: 256)
            for label in record.value.split(separator: ".") {
                let bytes = Array(label.utf8)
                rdata.writeInteger(UInt8(bytes.count), as: UInt8.self)
                rdata.writeBytes(bytes)
            }
            rdata.writeInteger(UInt8(0), as: UInt8.self)
            buf.writeInteger(UInt16(rdata.readableBytes), as: UInt16.self)
            buf.writeBuffer(&rdata)
        default:
            return nil
        }

        return buf
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
