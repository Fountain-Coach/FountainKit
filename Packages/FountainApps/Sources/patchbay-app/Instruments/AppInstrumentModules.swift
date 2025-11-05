import Foundation
import AppKit

enum InstrumentCapability: Hashable { case visualPreview, assistantUI, umpProducer, umpConsumer, propertyLinks }

protocol AppInstrumentModule {
    var kind: String { get }
    var category: String { get }
    var capabilities: Set<InstrumentCapability> { get }
    @MainActor func openPreviewIfAvailable(id: String, state: AppState, vm: EditorVM)
}

enum AppInstrumentRegistry {
    static func module(for kind: String) -> AppInstrumentModule? {
        switch kind {
        case "audiotalk.chat": return AudioTalkChatModule()
        case "mvk.triangle": return MVKTriangleModule()
        case "mvk.quad": return MVKQuadModule()
        case "saliency.quietFrame": return QuietFrameModule()
        case "csound.sonify": return CsoundSonifyModule()
        default: return nil
        }
    }
}

struct AudioTalkChatModule: AppInstrumentModule {
    let kind = "audiotalk.chat"
    let category = "Assistant.Chat"
    let capabilities: Set<InstrumentCapability> = [.assistantUI, .propertyLinks]
    @MainActor func openPreviewIfAvailable(id: String, state: AppState, vm: EditorVM) {
        ChatInstrumentManager.shared.open(for: id)
    }
}

struct MVKTriangleModule: AppInstrumentModule {
    let kind = "mvk.triangle"
    let category = "Visual.Renderer.Metal"
    let capabilities: Set<InstrumentCapability> = [.visualPreview, .umpProducer, .umpConsumer, .propertyLinks]
    @MainActor func openPreviewIfAvailable(id: String, state: AppState, vm: EditorVM) {
        // Preview window not yet implemented; no-op
    }
}

struct MVKQuadModule: AppInstrumentModule {
    let kind = "mvk.quad"
    let category = "Visual.Renderer.Metal"
    let capabilities: Set<InstrumentCapability> = [.visualPreview, .umpProducer, .umpConsumer, .propertyLinks]
    @MainActor func openPreviewIfAvailable(id: String, state: AppState, vm: EditorVM) {
        // Preview window not yet implemented; no-op
    }
}

struct QuietFrameModule: AppInstrumentModule {
    let kind = "saliency.quietFrame"
    let category = "Vision.Saliency"
    let capabilities: Set<InstrumentCapability> = [.propertyLinks]
    @MainActor func openPreviewIfAvailable(id: String, state: AppState, vm: EditorVM) {
        // Visual is rendered on canvas directly; no separate preview for now
    }
}

struct CsoundSonifyModule: AppInstrumentModule {
    let kind = "csound.sonify"
    let category = "Audio.Sonification"
    let capabilities: Set<InstrumentCapability> = [.umpConsumer]
    @MainActor func openPreviewIfAvailable(id: String, state: AppState, vm: EditorVM) {
        // External audio process; nothing to preview here
    }
}
