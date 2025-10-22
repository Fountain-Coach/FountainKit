import Foundation
import SecretStore

public enum SecretStoreHelper {
    public static func read(service: String, account: String) -> String? {
        // Allow disabling interactive secret backends (Keychain/libsecret)
        // via environment to prevent repeated auth prompts in CLI apps.
        let env = ProcessInfo.processInfo.environment
        if (env["FK_NO_KEYCHAIN"] == "1") || (env["FOUNTAIN_NO_KEYCHAIN"] == "1") || (env["SECRETSTORE_DISABLE"] == "1") {
            return nil
        }
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
