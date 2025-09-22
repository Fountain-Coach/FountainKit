#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let log = root.appendingPathComponent(".fountain/logs/diagnostics.log")
try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
let stamp = ISO8601DateFormatter().string(from: Date())
let message = "[diagnostics] \(stamp) - Control plane probe executed\n"
if FileManager.default.fileExists(atPath: log.path) {
    let handle = try FileHandle(forWritingTo: log)
    try handle.seekToEnd()
    if let data = message.data(using: .utf8) { handle.write(data) }
    try handle.close()
} else {
    try message.write(to: log, atomically: true, encoding: .utf8)
}
print("Diagnostics script touched \(log.path)")
