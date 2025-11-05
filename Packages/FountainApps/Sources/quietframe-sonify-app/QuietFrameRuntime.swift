import Foundation

@MainActor enum QuietFrameRuntime {
    private static var _recState: String = "idle"
    static func getRecState() -> String { _recState }
    static func setRecState(_ s: String) { _recState = s }
}

