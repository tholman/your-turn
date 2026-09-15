import SwiftUI

/// Slides in above the writing area: theme, text size, width, keys, history.
struct SettingsDrawer: View {
    @Environment(\.look) private var look
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var keymap = Keymap.shared

    private let fixedKeys: [(key: String, what: String)] = [
        ("esc", "Cancel"), ("⇧↩", "Line break inside a paragraph"), ("- ␣", "Bullet list"),
        ("1. ␣", "Numbered list"), ("## ␣", "Heading"), ("⌘1 … ⌘9", "Tick a point"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            choice("Theme", Settings.ThemeMode.allCases, settings.theme) { settings.theme = $0 }
            HStack(alignment: .firstTextBaseline, spacing: 36) {
                choice("Text", Settings.TextSize.allCases, settings.textSize) { settings.textSize = $0 }
                choice("Width", Settings.Width.allCases, settings.width) { settings.width = $0 }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    label("Keys")
                    Text("click one, press the new keys")
                        .font(Theme.font(11))
                        .foregroundStyle(look.mute)
                    Spacer()
                    Button("Reset", action: keymap.reset)
                        .buttonStyle(.plain)
                        .font(Theme.font(11, "Medium"))
                        .foregroundStyle(look.mute)
                    Button("History…") { NSWorkspace.shared.activateFileViewerSelecting([History.fileURL]) }
                        .buttonStyle(.plain)
                        .font(Theme.font(11, "Medium"))
                        .foregroundStyle(look.mute)
                        .help("Every send is kept in history.jsonl")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(KeyAction.allCases, id: \.rawValue) { action in
                        HStack(spacing: 10) {
                            KeyRecorder(binding: keymap.binding(action)) { keymap.set(action, $0) }
                                .frame(width: 84, height: 24)
                            Text(action.label)
                                .font(Theme.font(12))
                                .foregroundStyle(look.mute)
                        }
                    }
                    ForEach(fixedKeys, id: \.what) { row in
                        HStack(spacing: 10) {
                            Text(row.key)
                                .font(Theme.font(11, "DemiBold"))
                                .foregroundStyle(look.ink)
                                .frame(width: 84, height: 24)
                                .background(RoundedRectangle(cornerRadius: 6).strokeBorder(look.hairline))
                            Text(row.what)
                                .font(Theme.font(12))
                                .foregroundStyle(look.mute)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: look.measure)
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 36)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Theme.serif(15))
            .foregroundStyle(look.ink)
    }

    /// A row of pills; the chosen one is ink on the tint.
    private func choice<T: Hashable>(_ title: String, _ options: [T], _ current: T, name: @escaping (T) -> String = { "\($0)" }, select: @escaping (T) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            label(title)
            HStack(spacing: 4) {
                ForEach(options, id: \.self) { option in
                    let on = option == current
                    Button { select(option) } label: {
                        Text(displayName(option))
                            .font(Theme.font(12, on ? "DemiBold" : "Medium"))
                            .foregroundStyle(on ? look.ink : look.mute)
                            .fixedSize()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(on ? look.accent.opacity(0.16) : Color.clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func displayName<T>(_ option: T) -> String {
        if let theme = option as? Settings.ThemeMode { return theme.label }
        if let size = option as? Settings.TextSize { return size.label }
        if let width = option as? Settings.Width { return width.label }
        return "\(option)"
    }
}
