import SwiftUI
import AppKit

struct FocusTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var initialFocus: Bool = false

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField(string: text)
        tf.isBezeled = true
        tf.isEditable = true
        tf.isSelectable = true
        tf.usesSingleLineMode = true
        tf.lineBreakMode = .byClipping
        tf.placeholderString = placeholder
        tf.delegate = context.coordinator
        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
        nsView.placeholderString = placeholder
        if initialFocus {
            FocusManager.ensureFocus(nsView)
            FocusManager.guardModalFocus(nsView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusTextField
        init(_ parent: FocusTextField) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            if let tf = obj.object as? NSTextField { parent.text = tf.stringValue }
        }
    }
}
