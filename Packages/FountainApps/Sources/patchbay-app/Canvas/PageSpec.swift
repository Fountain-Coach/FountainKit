import CoreGraphics

enum PageSpec {
    // A4 in PDF points (1pt = 1/72 in; 1in = 25.4mm)
    static let a4Portrait: CGSize = CGSize(width: 595.28, height: 841.89)
    static let a4Landscape: CGSize = CGSize(width: 841.89, height: 595.28)

    static func mm(_ value: CGFloat) -> CGFloat { value * 72.0 / 25.4 }
}

