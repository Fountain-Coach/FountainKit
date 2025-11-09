import SwiftUI

public enum MidiMapTokens {
    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let s: CGFloat  = 6
        public static let m: CGFloat  = 10
        public static let l: CGFloat  = 14
        public static let xl: CGFloat = 20
    }
    public enum Colors {
        public static let grid = Color.white.opacity(0.13)
        public static let tileOn = Color(red: 0.23, green: 0.51, blue: 1.0)
        public static let tileHover = Color.white.opacity(0.07)
        public static let hatch = Color.white.opacity(0.06)
        public static let keyline = Color.white.opacity(0.9)
    }
}

