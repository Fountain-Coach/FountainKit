import Foundation
import CryptoKit

struct FileHasher {
    func sha256(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return sha256(data: data)
    }

    func sha256(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
