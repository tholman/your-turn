import SwiftUI

/// What changed against the draft, rendered like the page: insertions underlined in teal,
/// deletions struck in grey, headings and lists as they are in the editor.
struct DiffView: View {
    @Environment(\.look) private var look
    var text: NSAttributedString

    var body: some View {
        ScrollView {
            ReadOnlyText(text: text)
                .frame(maxWidth: look.measure, alignment: .leading)
                .padding(.horizontal, Layout.gutter)
                .padding(.top, 52)
                .padding(.bottom, 120)
                .frame(maxWidth: .infinity)
        }
    }
}

/// The editor's text view, frozen. Grows with its content; the parent scrolls.
struct ReadOnlyText: NSViewRepresentable {
    var text: NSAttributedString

    func makeNSView(context: Context) -> RichTextView {
        let view = RichTextView.make()
        view.isEditable = false
        view.isSelectable = true
        view.textStorage?.setAttributedString(text)
        return view
    }

    func updateNSView(_ view: RichTextView, context: Context) {
        if !view.attributedString().isEqual(text) { view.textStorage?.setAttributedString(text) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: RichTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: max(32, view.height(forWidth: width)))
    }
}
