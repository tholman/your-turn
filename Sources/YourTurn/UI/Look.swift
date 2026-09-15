import SwiftUI

/// The current palette and measure, passed through the environment so a theme change recolours
/// views in place instead of rebuilding them.
struct Look: Equatable {
    var theme: Settings.ThemeMode
    var width: Settings.Width

    var canvas: Color   { Theme.canvas }
    var sidebar: Color  { Theme.sidebar }
    var hairline: Color { Theme.hairline }
    var ink: Color      { Theme.ink }
    var mute: Color     { Theme.mute }
    var accent: Color   { Theme.accent }
    var measure: CGFloat { width.measure }
}

private struct LookKey: EnvironmentKey {
    static let defaultValue = Look(theme: .system, width: .regular)
}

extension EnvironmentValues {
    var look: Look {
        get { self[LookKey.self] }
        set { self[LookKey.self] = newValue }
    }
}
