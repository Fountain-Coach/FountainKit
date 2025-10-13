import Foundation
import SecretStore

public enum SecretStoreHelper {
    public static func read(service: String, account: String) -> String? {
#if canImport(Security)
        let store = KeychainStore(service: service)
#else
        let store = SecretServiceStore(service: service)
#endif
        do {
            guard let data = try store.retrieveSecret(for: account) else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
