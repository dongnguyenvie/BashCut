import AppKit
import SwiftUI

/// Keys the chat input hands to its owner before the text view acts on them.
enum ChatInputKey { case submit, up, down, tab, escape }

/// The chat-agent message box: Enter sends, Shift+Enter or Option+Enter inserts a new line. While an input method is
/// composing (Vietnamese Telex, for example) Enter only commits the text, because AppKit then never asks the delegate.
/// Arrows, Tab and Escape go to `onKey` first, for the slash-command menu; it returns whether it used the key.
struct ChatInputView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onKey: (ChatInputKey) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.setAccessibilityLabel(placeholder)
        textView.string = text
        context.coordinator.textView = textView
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NSTextView, !textView.hasMarkedText(), textView.string != text
        else { return }
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInputView
        weak var textView: NSTextView?

        init(_ parent: ChatInputView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) || flags.contains(.option) {
                    textView.insertText("\n", replacementRange: textView.selectedRange())
                    return true
                }
                return parent.onKey(.submit) || true
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), #selector(NSResponder.insertLineBreak(_:)):
                textView.insertText("\n", replacementRange: textView.selectedRange())
                return true
            case #selector(NSResponder.moveUp(_:)): return parent.onKey(.up)
            case #selector(NSResponder.moveDown(_:)): return parent.onKey(.down)
            case #selector(NSResponder.insertTab(_:)): return parent.onKey(.tab)
            case #selector(NSResponder.cancelOperation(_:)): return parent.onKey(.escape)
            default: return false
            }
        }
    }
}
