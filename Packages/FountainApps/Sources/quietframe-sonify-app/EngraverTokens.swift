import Foundation

// EngraverTokens — lightweight spacing/metric tokens inspired by ScoreKit/RulesKit
// These keep GUI spacing deterministic without adding dependencies here.
enum EngraverTokens {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat  = 6
        static let m: CGFloat  = 10
        static let l: CGFloat  = 14
        static let xl: CGFloat = 20
    }
    enum Metrics {
        static let toolbarControlWidth: CGFloat = 120
        static let toolbarCornerRadius: CGFloat = 6
    }
}

