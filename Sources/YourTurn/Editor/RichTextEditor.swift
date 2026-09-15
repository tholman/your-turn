import SwiftUI

/// Lets SwiftUI chrome reach the text view: focus it, apply a link, read its focus state.
final class EditorHandle: ObservableObject {
    weak var view: RichTextView?
    @Published var focused = false

    func focusThen(_ action: (RichTextView) -> Void) {
        guard let view = view else { return }
        view.window?.makeFirstResponder(view)
        action(view)
    }
}

/// SwiftUI wrapper for RichTextView. Grows with its content; the parent scrolls.
struct RichTextEditor: NSViewRepresentable {
    @Binding var text: NSAttributedString
    @ObservedObject var handle: EditorHandle

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> RichTextView {
        let view = RichTextView.make()
        view.delegate = context.coordinator
        view.textStorage?.setAttributedString(text)
        view.highlightAsides()
        context.coordinator.current = text
        view.onFocusChange = { [weak handle] focused in DispatchQueue.main.async { handle?.focused = focused } }
        handle.view = view
        return view
    }

    func updateNSView(_ view: RichTextView, context: Context) {
        context.coordinator.parent = self
        // Identity, not equality: the text view normalises attributes, so an equality check
        // would re-push the model text on every render and throw the caret to the end.
        if text !== context.coordinator.current {
            context.coordinator.current = text
            view.textStorage?.setAttributedString(text)
            view.highlightAsides()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: RichTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: max(32, view.height(forWidth: width)))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var current: NSAttributedString?

        init(_ parent: RichTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            let text = view.attributedString()
            current = text
            parent.text = text
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            // Keyboard selection and collapse; drags are handled in mouseDown.
            guard let view = notification.object as? RichTextView, NSEvent.pressedMouseButtons == 0 else { return }
            view.updateHoverBar()
        }
    }
}
