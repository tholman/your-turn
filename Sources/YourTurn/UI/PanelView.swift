import SwiftUI

enum Layout {
    static let sidebarWidth: CGFloat = 300
    static let gutter: CGFloat = 40
    static var measure: CGFloat { Settings.shared.width.measure }   // max line length
}

/// Sidebar of points and links on the left, the writing column on the right, actions below.
struct PanelView: View {
    @Environment(\.look) private var look
    @ObservedObject var model: EditorModel
    @ObservedObject private var settings = Settings.shared
    var onSend: () -> Void
    var onCancel: () -> Void
    var onConfirm: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            columns
            if let confirmation = model.confirmation {
                ConfirmationCard(confirmation: confirmation, onConfirm: onConfirm, onDismiss: onDismiss)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.confirmation != nil)
        .ignoresSafeArea()
        .frame(minWidth: 820, minHeight: 520)
        .environment(\.look, Look(theme: settings.theme, width: settings.width))
    }

    private var columns: some View {
        HStack(spacing: 0) {
            Sidebar(model: model)
                .frame(width: Layout.sidebarWidth)
                .background(
                    ZStack {
                        // Paper is opaque by nature; the others let the desktop glow through.
                        if look.theme != .paper { Vibrancy() }
                        look.sidebar.opacity(look.theme == .paper ? 1 : 0.72)
                    }
                )
            Rectangle().fill(look.hairline).frame(width: 1)
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    if model.showDiff {
                        DiffView(text: model.diffText)
                    } else {
                        WritingArea(model: model)
                    }
                    // Settings slide down over the text; nothing underneath moves.
                    if model.showSettings {
                        SettingsDrawer()
                            .background(
                                Rectangle()
                                    .fill(look.canvas)
                                    .shadow(color: .black.opacity(0.1), radius: 18, y: 8)
                            )
                            .overlay(alignment: .bottom) { Rectangle().fill(look.hairline).frame(height: 1) }
                            .transition(.move(edge: .top))
                            .zIndex(1)
                    }
                }
                .clipped()
                Rectangle().fill(look.hairline).frame(height: 1)
                Footer(model: model, onSend: onSend, onCancel: onCancel)
            }
            .background(look.canvas)
            .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45), value: model.showSettings)
        }
    }
}

/// A quiet card in the panel's own style, in place of a system alert. Return confirms, Esc keeps editing.
struct ConfirmationCard: View {
    @Environment(\.look) private var look
    var confirmation: EditorModel.Confirmation
    var onConfirm: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            look.ink.opacity(0.12).onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 10) {
                Text(confirmation.title)
                    .font(Theme.serif(20))
                    .foregroundStyle(look.ink)
                Text(confirmation.detail)
                    .font(Theme.font(13))
                    .foregroundStyle(look.mute)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Spacer()
                    Button(action: onDismiss) {
                        Text("Keep editing")
                            .font(Theme.font(13, "Medium"))
                            .foregroundStyle(look.mute)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    Button(action: onConfirm) {
                        Text(confirmation.confirm)
                            .font(Theme.font(13, "DemiBold"))
                            .foregroundStyle(look.canvas)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(look.ink))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 8)
            }
            .padding(26)
            .frame(width: 420)
            .background(RoundedRectangle(cornerRadius: 14).fill(look.canvas))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(look.hairline))
            .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
        }
    }
}
