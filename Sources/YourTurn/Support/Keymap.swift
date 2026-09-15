import AppKit
import Combine

/// Customisable key bindings. Overrides live in ~/Library/Application Support/your-turn/keys.json as
/// {"send": "cmd+return", "bold": "cmd+b", ...}. Tokens: cmd, shift, alt, ctrl, return, esc, slash, a letter or digit.
enum KeyAction: String, CaseIterable {
    case send, bold, italic, link, note, lookup, addPoint, diff, keys

    var label: String {
        switch self {
        case .send: return "Send"
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .link: return "Link the selection"
        case .note: return "Note about the selection"
        case .lookup: return "Look up in Dictionary"
        case .addPoint: return "Add a point"
        case .diff: return "Show changes"
        case .keys: return "Settings and keys"
        }
    }
}

struct KeyBinding: Equatable {
    var key: String                       // NSMenuItem key equivalent: a lowercase letter, digit, "\r" or "/"
    var mods: NSEvent.ModifierFlags

    /// "cmd+shift+n" → binding. Any unknown token fails the whole string.
    static func parse(_ string: String) -> KeyBinding? {
        var mods: NSEvent.ModifierFlags = []
        var key: String?
        for token in string.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch token {
            case "cmd", "command", "⌘": mods.insert(.command)
            case "shift", "⇧": mods.insert(.shift)
            case "alt", "option", "opt", "⌥": mods.insert(.option)
            case "ctrl", "control", "⌃": mods.insert(.control)
            case "return", "enter", "↩": key = "\r"
            case "slash": key = "/"
            default:
                guard token.count == 1, let character = token.first,
                      character.isLetter || character.isNumber || "/.,;'[]-=`".contains(character) else { return nil }
                key = token
            }
        }
        guard let key = key else { return nil }
        return KeyBinding(key: key, mods: mods)
    }

    /// "⌘⇧N", "⌘↩".
    var display: String {
        var out = ""
        if mods.contains(.control) { out += "⌃" }
        if mods.contains(.option) { out += "⌥" }
        if mods.contains(.shift) { out += "⇧" }
        if mods.contains(.command) { out += "⌘" }
        out += key == "\r" ? "↩" : key.uppercased()
        return out
    }

    /// The file syntax: "cmd+shift+n".
    var source: String {
        var parts: [String] = []
        if mods.contains(.control) { parts.append("ctrl") }
        if mods.contains(.option) { parts.append("alt") }
        if mods.contains(.shift) { parts.append("shift") }
        if mods.contains(.command) { parts.append("cmd") }
        parts.append(key == "\r" ? "return" : (key == "/" ? "slash" : key))
        return parts.joined(separator: "+")
    }
}

final class Keymap: ObservableObject {
    static let shared = Keymap()

    static let defaults: [KeyAction: KeyBinding] = [
        .send: KeyBinding(key: "\r", mods: [.command]),
        .bold: KeyBinding(key: "b", mods: [.command]),
        .italic: KeyBinding(key: "i", mods: [.command]),
        .link: KeyBinding(key: "k", mods: [.command]),
        .note: KeyBinding(key: "m", mods: [.command, .shift]),
        .lookup: KeyBinding(key: "d", mods: [.command]),
        .addPoint: KeyBinding(key: "n", mods: [.command, .shift]),
        .diff: KeyBinding(key: "d", mods: [.command, .shift]),
        .keys: KeyBinding(key: "/", mods: [.command]),
    ]

    static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("your-turn")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("keys.json")
    }

    @Published private(set) var bindings = Keymap.defaults
    private var menuItems: [KeyAction: NSMenuItem] = [:]

    func binding(_ action: KeyAction) -> KeyBinding { bindings[action] ?? Keymap.defaults[action]! }

    /// Reads the override file. Bad entries are ignored, so a typo never loses the defaults.
    func load(from url: URL = Keymap.fileURL) {
        bindings = Keymap.defaults
        guard let data = try? Data(contentsOf: url),
              let overrides = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
        apply(overrides: overrides)
    }

    func apply(overrides: [String: String]) {
        for (name, value) in overrides {
            guard let action = KeyAction(rawValue: name), let binding = KeyBinding.parse(value) else { continue }
            bindings[action] = binding
        }
        for (action, item) in menuItems { set(item, binding(action)) }
    }

    /// Records a new binding, applies it to the menus and writes the file.
    func set(_ action: KeyAction, _ binding: KeyBinding) {
        bindings[action] = binding
        if let item = menuItems[action] { set(item, binding) }
        save()
    }

    func reset() {
        bindings = Keymap.defaults
        for (action, item) in menuItems { set(item, binding(action)) }
        save()
    }

    func save(to url: URL = Keymap.fileURL) {
        let dictionary = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value.source) })
        if let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }

    func register(_ item: NSMenuItem, for action: KeyAction) {
        menuItems[action] = item
        set(item, binding(action))
    }

    private func set(_ item: NSMenuItem, _ binding: KeyBinding) {
        item.keyEquivalent = binding.key
        item.keyEquivalentModifierMask = binding.mods
    }
}
