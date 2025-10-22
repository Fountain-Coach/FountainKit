import Foundation
import SecretStore

public enum SecretStoreHelper {
    // In-process memoization to avoid repeated Keychain/libsecret lookups, which may
    // trigger OS prompts. We only read once per (service, account) per process.
    private static var cache: [String: String] = [:]
    private static var failures: Set<String> = []
    private static let lock = NSLock()

    public static func read(service: String, account: String) -> String? {
        // Allow disabling interactive secret backends (Keychain/libsecret)
        // via environment to prevent prompts in CI or headless runs.
        let env = ProcessInfo.processInfo.environment
        if (env["FK_NO_KEYCHAIN"] == "1") || (env["FOUNTAIN_NO_KEYCHAIN"] == "1") || (env["SECRETSTORE_DISABLE"] == "1") {
            return nil
        }

        let key = service + "#" + account
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        if failures.contains(key) { return nil }

#if canImport(Security)
        let store = KeychainStore(service: service)
#else
        let store = SecretServiceStore(service: service)
#endif
        do {
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
}
