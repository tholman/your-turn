import Foundation

/// Bullets ("•\t") and numbers ("N.\t") are their own paragraphs, marker first, text after a tab.
enum ListKind: Equatable {
    case bullet
    case number(Int)

    var marker: String {
        switch self {
        case .bullet: return TextStyle.bullet
        case .number(let n): return "\(n).\t"
        }
    }

    var next: ListKind {
        switch self {
        case .bullet: return .bullet
        case .number(let n): return .number(n + 1)
        }
    }

    func sameList(as other: ListKind?) -> Bool {
        switch (self, other) {
        case (.bullet, .bullet?), (.number, .number?): return true
        default: return false
        }
    }
}

enum Lists {
    /// The list marker at the start of a paragraph, and how many UTF-16 units it takes (marker + tab).
    static func prefix(of paragraph: String) -> (kind: ListKind, length: Int)? {
        if paragraph.hasPrefix(TextStyle.bullet) { return (.bullet, TextStyle.bullet.utf16.count) }
        guard let range = paragraph.range(of: "^\\d+\\.\\t", options: .regularExpression) else { return nil }
        return (.number(Int(paragraph[range].dropLast(2)) ?? 1), paragraph[range].utf16.count)
    }

    /// Markdown line → list kind and the text after the marker, if it is a list line.
    static func fromMarkdown(_ line: String) -> (kind: ListKind, body: String)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") { return (.bullet, String(line.dropFirst(2))) }
        if let range = line.range(of: "^\\d+\\. ", options: .regularExpression) {
            return (.number(Int(line[range].dropLast(2)) ?? 1), String(line[range.upperBound...]))
        }
        return nil
    }

    /// Editor paragraph → Markdown line.
    static func toMarkdown(_ paragraph: String) -> String {
        guard let p = prefix(of: paragraph) else { return paragraph }
        let body = String(paragraph.dropFirst(p.length))
        switch p.kind {
        case .bullet: return "- " + body
        case .number(let n): return "\(n). " + body
        }
    }
}
