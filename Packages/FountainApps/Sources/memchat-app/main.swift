import SwiftUI
import AppKit
import MemChatKit
import LauncherSignature

@main
struct MemChatApp: App {
    init() {
        verifyLauncherSignature()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    var body: some Scene {
        WindowGroup {
            MemChatView(configuration: .init(memoryCorpusId: ProcessInfo.processInfo.environment["MEMORY_CORPUS_ID"] ?? "memchat-app"))
                .frame(minWidth: 640, minHeight: 480)
        }
    }
}
