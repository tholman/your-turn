import SwiftUI

/// The writing column: one editor, top-centred at a comfortable measure.
struct WritingArea: View {
    @Environment(\.look) private var look
    @ObservedObject var model: EditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if model.text.length == 0 {
                        Text("Write here…")
                            .font(Theme.font(16))
                            .foregroundStyle(look.mute.opacity(0.6))
                            .padding(.top, 4)
                            .allowsHitTesting(false)
                    }
                    RichTextEditor(text: $model.text, handle: model.editor)
                }
                .frame(minHeight: 280, alignment: .top)
                Spacer(minLength: 120)
            }
            .frame(maxWidth: look.measure)
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 52)
            .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Clicking empty canvas below the text drops the caret at the end.
            model.editor.focusThen { $0.setSelectedRange(NSRange(location: $0.string.count, length: 0)) }
        }
    }
}
