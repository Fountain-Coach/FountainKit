import SwiftUI

@available(macOS 13.0, *)
struct ThreePane<Left: View, Middle: View, Right: View>: View {
    @State private var leftWidth: CGFloat
    @State private var rightWidth: CGFloat
    let minLeft: CGFloat
    let minRight: CGFloat
    let left: () -> Left
    let middle: () -> Middle
    let right: () -> Right

    init(minLeft: CGFloat = 260,
         minRight: CGFloat = 280,
         leftWidth: CGFloat = 320,
         rightWidth: CGFloat = 360,
         @ViewBuilder left: @escaping () -> Left,
         @ViewBuilder middle: @escaping () -> Middle,
         @ViewBuilder right: @escaping () -> Right) {
        self.minLeft = minLeft
        self.minRight = minRight
        _leftWidth = State(initialValue: leftWidth)
        _rightWidth = State(initialValue: rightWidth)
        self.left = left
        self.middle = middle
        self.right = right
    }

    var body: some View {
        HSplitView {
            left()
                .frame(minWidth: minLeft, idealWidth: leftWidth)
            HSplitView {
                middle()
                    .frame(minWidth: 420)
                right()
                    .frame(minWidth: minRight, idealWidth: rightWidth)
            }
        }
    }
}

