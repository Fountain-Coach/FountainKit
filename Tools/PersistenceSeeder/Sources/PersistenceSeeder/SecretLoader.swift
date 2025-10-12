import Foundation
import SecretStore

struct SecretLoader {
#if canImport(Security)
    private typealias Store = KeychainStore
#else
    private typealias Store = SecretServiceStore
#endif

    static func load(service: String, account: String) throws -> String? {
        let store = Store(service: service)
        guard let data = try store.retrieveSecret(for: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
