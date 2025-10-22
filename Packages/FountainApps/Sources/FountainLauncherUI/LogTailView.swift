import SwiftUI

struct LogTailView: View {
    let text: String
    let follow: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("LOG_BOTTOM")
                }
                .padding(.trailing, 2)
                .onChange(of: text) {
                    if follow { withAnimation(.linear(duration: 0.05)) { proxy.scrollTo("LOG_BOTTOM", anchor: .bottom) } }
                }
            }
        }
    }
}

