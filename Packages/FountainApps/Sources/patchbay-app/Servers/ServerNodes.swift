import Foundation

struct ServerMeta: Codable { let serviceId: String; let title: String; let port: Int; let specRelativePath: String }

func normalizeServerId(_ s: String) -> String {
    let lowered = s.lowercased()
    let allowed = lowered.map { ($0.isLetter || $0.isNumber) ? $0 : "-" }
    return String(allowed).replacingOccurrences(of: "--", with: "-")
}

