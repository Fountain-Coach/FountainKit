import SwiftUI
import AppKit

struct FocusTextView: NSViewRepresentable {
    @Binding var text: String
    var initialFocus: Bool = false
    var minHeight: CGFloat = 120

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let tv = NSTextView()
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        tv.string = text
        tv.delegate = context.coordinator
        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        var f = nsView.frame
        f.size.height = max(minHeight, f.size.height)
        nsView.frame = f
        if initialFocus {
            FocusManager.ensureFocus(tv)
            FocusManager.guardModalFocus(tv)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FocusTextView
        init(_ parent: FocusTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let tv = notification.object as? NSTextView { parent.text = tv.string }
        }
    }
}
