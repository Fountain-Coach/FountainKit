import Foundation

/// Abstraction over DNS providers used for certificate challenges and routing.
public protocol DNSProvider {
    /// Lists all zone identifiers available to the account.
    func listZones() async throws -> [String]
    /// Creates a new DNS record within the given zone.
    func createRecord(zone: String, name: String, type: String, value: String) async throws
    /// Updates an existing record with a new value.
    func updateRecord(id: String, zone: String, name: String, type: String, value: String) async throws
    /// Deletes a DNS record by identifier.
    func deleteRecord(id: String) async throws
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
