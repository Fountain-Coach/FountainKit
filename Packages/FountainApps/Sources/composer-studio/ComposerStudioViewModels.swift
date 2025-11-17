import Foundation
#if canImport(SwiftUI)
import SwiftUI
import composer_script_service
import composer_score_service
import composer_cues_service

@MainActor
final class ScriptViewModel: ObservableObject {
    private let core: composer_script_service.ComposerScriptCore

    @Published var scriptId: String
    @Published var sceneText: String

    init(core: composer_script_service.ComposerScriptCore = .init()) {
        self.core = core
        self.scriptId = core.scriptId
        self.sceneText = core.sceneSlice.text.joined(separator: "\n")
    }

    func reload() {
        scriptId = core.scriptId
        sceneText = core.sceneSlice.text.joined(separator: "\n")
    }
}

@MainActor
final class ScoreViewModel: ObservableObject {
    private let core: composer_score_service.ComposerScoreCore

    @Published var scoreId: String
    @Published var state: composer_score_service.Components.Schemas.ScoreState

    init(core: composer_score_service.ComposerScoreCore = .init(), scoreId: String = "default") {
        self.core = core
        self.scoreId = scoreId
        self.state = core.state(for: scoreId)
    }

    func load(scoreId: String) {
        self.scoreId = scoreId
        state = core.state(for: scoreId)
    }
}

@MainActor
final class CuesViewModel: ObservableObject {
    @Published var plannedSummary: String = ""
}

#endif

