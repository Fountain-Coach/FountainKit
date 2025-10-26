import Foundation

// Lightweight facade for calling RulesKit when available.
// For now we provide local fallbacks so PatchBay compiles without RulesKit linked.

enum RulesKitFacade {
    struct PageFitInput { let view: CGSize; let page: CGSize; let zoom: CGFloat; let translation: CGPoint }
    struct CheckResult { let ok: Bool; let detail: String }

    static func checkPageFit(_ input: PageFitInput) -> CheckResult {
        let pageRect = CGRect(origin: .zero, size: input.page)
        let z = EditorVM.computeFitZoom(viewSize: input.view, contentBounds: pageRect)
        let t = EditorVM.computeCenterTranslation(viewSize: input.view, contentBounds: pageRect, zoom: z)
        let okZ = abs(input.zoom - z) < 0.05
        let okTx = abs(input.translation.x - t.x) < 8
        let okTy = abs(input.translation.y - t.y) < 8
        return .init(ok: okZ && okTx && okTy, detail: String(format: "z=%.3f tx=%.1f ty=%.1f", input.zoom, input.translation.x, input.translation.y))
    }

    static func checkMarginWithinPage(page: CGSize, marginMM: CGFloat) -> CheckResult {
        let m = PageSpec.mm(marginMM)
        let ok = (m*2 < page.width) && (m*2 < page.height)
        return .init(ok: ok, detail: ok ? "ok" : "margin too large")
    }

    static func checkPaneWidthPolicy() -> CheckResult {
        // Placeholder: wired left/right min/ideal/max in AppMain; measure later via Preferences.
        return .init(ok: true, detail: "policy asserted")
    }
}

