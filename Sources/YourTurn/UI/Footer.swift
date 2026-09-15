import SwiftUI

/// Keys button, status, Cancel and Send, aligned to the writing column.
struct Footer: View {
    @Environment(\.look) private var look
    @ObservedObject var model: EditorModel
    var onSend: () -> Void
    var onCancel: () -> Void
    @State private var sendHover = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Button { model.showSettings.toggle() } label: {
                Image(systemName: "command")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.showSettings ? look.accent : look.mute.opacity(0.8))
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 6).strokeBorder(look.hairline))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings and keys")
            .help("Settings and keys  \(Keymap.shared.binding(.keys).display)")

            Text(status)
                .font(Theme.font(11))
                .foregroundStyle(look.mute)
                .monospacedDigit()

            if model.hasDraft {
                Button { model.showDiff.toggle() } label: {
                    Text(model.showDiff ? "Back to writing" : "Changes")
                        .font(Theme.font(11, "Medium"))
                        .foregroundStyle(model.showDiff ? look.accent : look.mute)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("What changed against the draft  \(Keymap.shared.binding(.diff).display)")
            }

            Spacer(minLength: 0)

            Button(action: onCancel) {
                Text("Cancel")
                    .font(Theme.font(13, "Medium"))
                    .foregroundStyle(look.mute)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Button(action: onSend) {
                HStack(spacing: 9) {
                    Text("Send")
                        .font(Theme.font(13, "DemiBold"))
                    Text(Keymap.shared.binding(.send).display)
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.6)
                }
                .foregroundStyle(sendHover ? Color.white : look.canvas)
                .fixedSize()
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Capsule().fill(sendHover ? look.accent : look.ink))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Send  \(Keymap.shared.binding(.send).display)")
            .onHover { sendHover = $0 }
            .animation(.easeInOut(duration: 0.18), value: sendHover)
        }
        .frame(maxWidth: look.measure)
        .padding(.horizontal, Layout.gutter)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    private var status: String { "\(model.wordCount) words" }
}
