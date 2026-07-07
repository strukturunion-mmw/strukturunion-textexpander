import SwiftUI
import AppKit

/// A plain / monospaced NSTextView wrapper for snippet content and scripts.
struct CodeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isMonospaced: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = font
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selected.location, text.utf16.count), length: 0))
        }
        textView.font = font
    }

    private var font: NSFont {
        isMonospaced
            ? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            : NSFont.systemFont(ofSize: 13)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: CodeTextEditor
        init(_ parent: CodeTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

/// A rich-text (RTFD) editor storing formatted data plus a plain mirror.
struct RichTextEditor: NSViewRepresentable {
    @Binding var rtfData: Data?
    @Binding var plainMirror: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.allowsImageEditing = true
        textView.importsGraphics = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.font = NSFont.systemFont(ofSize: 13)
        if let rtfData,
           let attributed = try? NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attributed)
        } else {
            textView.string = plainMirror
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {}

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: RichTextEditor
        init(_ parent: RichTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let storage = textView.textStorage else { return }
            let range = NSRange(location: 0, length: storage.length)
            parent.rtfData = storage.rtfd(from: range, documentAttributes: [
                .documentType: NSAttributedString.DocumentType.rtfd
            ])
            parent.plainMirror = storage.string
        }
    }
}
