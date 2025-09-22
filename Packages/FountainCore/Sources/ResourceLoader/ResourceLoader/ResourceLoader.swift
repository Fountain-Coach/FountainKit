import Foundation

public enum ResourceError: Error, LocalizedError {
  case missing(String)
  case unreadable(String, underlying: Error)

  public var errorDescription: String? {
    switch self {
    case .missing(let path):
      return "Resource missing: \(path). Add it under Resources and register in Package.swift."
    case .unreadable(let desc, let underlying):
      return "Failed to read resource: \(desc). Underlying: \(underlying)"
    }
  }
}

public struct ResourceLoader {
  public static func url(_ name: String, ext: String, subdir: String?, bundle: Bundle) throws -> URL {
    if let u = bundle.url(forResource: name, withExtension: ext, subdirectory: subdir) {
      return u
    }
    throw ResourceError.missing([subdir, "\(name).\(ext)"].compactMap { $0 }.joined(separator: "/"))
  }

  public static func data(_ name: String, ext: String, subdir: String?, bundle: Bundle) throws -> Data {
    let u = try url(name, ext: ext, subdir: subdir, bundle: bundle)
    do { return try Data(contentsOf: u) }
    catch { throw ResourceError.unreadable(u.path, underlying: error) }
  }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
