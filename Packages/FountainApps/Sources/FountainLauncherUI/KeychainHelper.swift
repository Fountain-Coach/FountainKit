import Foundation
import SecretStore

@MainActor
enum KeychainHelper {
    private static var cache: [String: String] = [:]
    private static var failures: Set<String> = []
    private static let lock = NSLock()
    static func save(service: String, account: String, secret: String) -> Bool {
        do {
            let store = makeStore(for: service)
            try store.storeSecret(Data(secret.utf8), for: account)
            return true
        } catch {
            return false
        }
    }

    static func read(service: String, account: String) -> String? {
        let key = service + "#" + account
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        if failures.contains(key) { return nil }
        do {
            let store = makeStore(for: service)
            guard let data = try store.retrieveSecret(for: account), let value = String(data: data, encoding: .utf8), !value.isEmpty else {
                failures.insert(key)
                return nil
            }
            cache[key] = value
            return value
        } catch {
            failures.insert(key)
            return nil
        }
    }

    static func delete(service: String, account: String) -> Bool {
        do {
            let store = makeStore(for: service)
            try store.deleteSecret(for: account)
            return true
        } catch {
#if !canImport(Security)
            if let error = error as? SecretServiceError {
                switch error {
                case .commandFailed(let code, _) where code == 1:
                    return true
                default:
                    break
                }
            }
#endif
            return false
        }
    }

#if canImport(Security)
    private static func makeStore(for service: String) -> KeychainStore {
        KeychainStore(service: service)
    }
#else
    private static func makeStore(for service: String) -> SecretServiceStore {
        SecretServiceStore(service: service)
    }
#endif
}
