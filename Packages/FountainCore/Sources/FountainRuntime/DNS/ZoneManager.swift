import Foundation
import Yams
import Dispatch
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Actor responsible for managing DNS zones and records with persistent YAML storage.
public actor ZoneManager {
    public struct Record: Codable, Sendable {
        public let id: UUID
        public var name: String
        public var type: String
        public var value: String
    }

    public struct RecordKey: Hashable, Sendable {
        public let name: String
        public let type: String
        public init(name: String, type: String) {
            self.name = name
            self.type = type
        }
    }

    public struct Zone: Codable, Sendable {
        public let id: UUID
        public var name: String
        public var records: [UUID: Record]
    }

    private var zones: [UUID: Zone]
    private let fileURL: URL
    private let signer: DNSSECSigner?
    private var timer: DispatchSourceTimer?
    private var lastModified: Date
    private let enableGitCommits: Bool
    private let updateContinuation: AsyncStream<[RecordKey: Record]>.Continuation
    public nonisolated let updates: AsyncStream<[RecordKey: Record]>

    /// Loads the zone cache from the provided YAML file if it exists.
    /// - Parameters:
    ///   - fileURL: Location of the YAML zone file on disk.
    ///   - signer: Optional DNSSEC signer used to generate zone signatures.
    public init(fileURL: URL, signer: DNSSECSigner? = nil, enableGitCommits: Bool = true) throws {
        self.fileURL = fileURL
        self.signer = signer
        self.enableGitCommits = enableGitCommits
        var continuation: AsyncStream<[RecordKey: Record]>.Continuation!
        self.updates = AsyncStream { continuation = $0 }
        self.updateContinuation = continuation
        if let data = try? Data(contentsOf: fileURL),
           let string = String(data: data, encoding: .utf8),
           let loaded = try? YAMLDecoder().decode([UUID: Zone].self, from: string) {
            self.zones = loaded
        } else {
            self.zones = [:]
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        self.lastModified = (attrs?[.modificationDate] as? Date) ?? Date()
        var map: [RecordKey: Record] = [:]
        for zone in zones.values {
            for record in zone.records.values {
                let fqdn = record.name.isEmpty ? zone.name : "\(record.name).\(zone.name)"
                map[RecordKey(name: fqdn, type: record.type)] = record
            }
        }
        updateContinuation.yield(map)
        Task { await self.startWatching() }
    }

    // MARK: - Zone operations
    public func listZones() -> [Zone] { Array(zones.values) }

    public func createZone(name: String) throws -> Zone {
        let zone = Zone(id: UUID(), name: name, records: [:])
        zones[zone.id] = zone
        try persist()
        return zone
    }

    public func deleteZone(id: UUID) throws -> Bool {
        if zones.removeValue(forKey: id) != nil {
            try persist()
            return true
        }
        return false
    }

    // MARK: - Record operations
    public func listRecords(zoneId: UUID) -> [Record]? {
        zones[zoneId]?.records.values.map { $0 }
    }

    public func createRecord(zoneId: UUID, name: String, type: String, value: String) throws -> Record? {
        guard var zone = zones[zoneId] else { return nil }
        let record = Record(id: UUID(), name: name, type: type, value: value)
        zone.records[record.id] = record
        zones[zoneId] = zone
        try persist()
        return record
    }

    public func updateRecord(zoneId: UUID, recordId: UUID, name: String, type: String, value: String) throws -> Record? {
        guard var zone = zones[zoneId], zone.records[recordId] != nil else { return nil }
        let record = Record(id: recordId, name: name, type: type, value: value)
        zone.records[recordId] = record
        zones[zoneId] = zone
        try persist()
        return record
    }

    public func deleteRecord(zoneId: UUID, recordId: UUID) throws -> Bool {
        guard var zone = zones[zoneId], zone.records.removeValue(forKey: recordId) != nil else { return false }
        zones[zoneId] = zone
        try persist()
        return true
    }

    /// Retrieves a record for the given fully qualified name and type.
    public func record(name: String, type: String) -> Record? {
        allRecords()[RecordKey(name: name, type: type)]
    }

    /// Returns the current in-memory zone cache as a flattened map keyed by name and type.
    public func allRecords() -> [RecordKey: Record] {
        var map: [RecordKey: Record] = [:]
        for zone in zones.values {
            for record in zone.records.values {
                let fqdn = record.name.isEmpty ? zone.name : "\(record.name).\(zone.name)"
                map[RecordKey(name: fqdn, type: record.type)] = record
            }
        }
        return map
    }

    private func persist() throws {
        let yaml = try YAMLEncoder().encode(zones)
        try yaml.write(to: fileURL, atomically: true, encoding: .utf8)
        if let signer {
            let sig = try signer.sign(zone: yaml)
            try Data(sig).write(to: fileURL.appendingPathExtension("sig"))
        }
        if enableGitCommits {
            gitCommit(message: "Update zone file")
        }
        let snapshot = allRecords()
        updateContinuation.yield(snapshot)
    }

    /// Reloads the zone cache from disk when the file has changed.
    public func reload() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let mod = attrs?[.modificationDate] as? Date,
           mod > lastModified,
           let data = try? Data(contentsOf: fileURL),
           let string = String(data: data, encoding: .utf8),
           let loaded = try? YAMLDecoder().decode([UUID: Zone].self, from: string) {
            zones = loaded
            lastModified = mod
            let snapshot = allRecords()
            updateContinuation.yield(snapshot)
        }
    }

    private func startWatching() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler(handler: { @Sendable [weak self] in
            Task { await self?.reload() }
        })
        timer.resume()
        self.timer = timer
    }

    private func gitCommit(message: String) {
        let dir = fileURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) else { return }

        let add = Process()
        add.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        add.currentDirectoryURL = dir
        add.arguments = ["add", fileURL.lastPathComponent]
        try? add.run()
        add.waitUntilExit()

        let commit = Process()
        commit.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commit.currentDirectoryURL = dir
        commit.arguments = ["commit", "-m", message]
        commit.environment = [
            "GIT_AUTHOR_NAME": "Codex",
            "GIT_AUTHOR_EMAIL": "codex@example.com",
            "GIT_COMMITTER_NAME": "Codex",
            "GIT_COMMITTER_EMAIL": "codex@example.com"
        ]
        try? commit.run()
        commit.waitUntilExit()
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
