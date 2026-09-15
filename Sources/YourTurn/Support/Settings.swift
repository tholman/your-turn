import AppKit
import Combine

/// User preferences, persisted in UserDefaults. Theme and width apply live; text size re-fits the open text.
final class Settings: ObservableObject {
    static let shared = Settings()

    enum ThemeMode: String, CaseIterable { case system, light, dark, paper
        var label: String { rawValue.capitalized }
    }
    enum TextSize: String, CaseIterable { case small, regular, large
        var label: String { rawValue.capitalized }
        var points: CGFloat { self == .small ? 15 : self == .regular ? 16 : 18 }
    }
    enum Width: String, CaseIterable { case narrow, regular, wide
        var label: String { rawValue.capitalized }
        var measure: CGFloat { self == .narrow ? 520 : self == .regular ? 620 : 760 }
    }

    /// Set by render flags so a `--theme` used for a screenshot is never saved as a preference.
    var transient = false

    @Published var theme: ThemeMode { didSet { if !transient { defaults.set(theme.rawValue, forKey: "theme") } } }
    @Published var textSize: TextSize { didSet { if !transient { defaults.set(textSize.rawValue, forKey: "textSize") } } }
    @Published var width: Width { didSet { if !transient { defaults.set(width.rawValue, forKey: "width") } } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = ThemeMode(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        textSize = TextSize(rawValue: defaults.string(forKey: "textSize") ?? "") ?? .regular
        width = Width(rawValue: defaults.string(forKey: "width") ?? "") ?? .regular
    }

    /// The NSAppearance a panel should adopt, or nil to follow the system.
    var appearance: NSAppearance? {
        switch theme {
        case .system: return nil
        case .light, .paper: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    static var folder: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("your-turn")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
