import AppKit

/// Word-level diff between the draft and the current text, for the Changes view.
enum Diff {
    enum Kind { case equal, insert, delete }
    struct Segment: Equatable {
        var kind: Kind
        var text: String
    }

    /// Tokens are words with their trailing whitespace, so joining equal runs reproduces the text.
    static func tokens(_ string: String) -> [String] {
        var out: [String] = []
        var current = ""
        for character in string {
            current.append(character)
            if character.isWhitespace || character.isNewline {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    static func words(old: String, new: String) -> [Segment] {
        let a = tokens(old), b = tokens(new)
        // Words compare without their whitespace; equal runs are emitted with the new text's spacing.
        let wa = a.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let wb = b.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let n = a.count, m = b.count
        // Longest common subsequence table, sized for a few thousand words either side.
        var table = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = wa[i] == wb[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var segments: [Segment] = []
        func add(_ kind: Kind, _ text: String) {
            if let last = segments.last, last.kind == kind { segments[segments.count - 1].text += text } else { segments.append(Segment(kind: kind, text: text)) }
        }
        var i = 0, j = 0
        while i < n, j < m {
            if wa[i] == wb[j] { add(.equal, b[j]); i += 1; j += 1 }
            else if table[i + 1][j] >= table[i][j + 1] { add(.delete, a[i]); i += 1 }
            else { add(.insert, b[j]); j += 1 }
        }
        while i < n { add(.delete, a[i]); i += 1 }
        while j < m { add(.insert, b[j]); j += 1 }
        return segments
    }

    /// The new text with insertions underlined and deletions struck in place, keeping the editor's
    /// fonts, headings and list styles, so the Changes view reads like the page itself.
    static func attributed(old: NSAttributedString, new: NSAttributedString) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var oldOffset = 0, newOffset = 0
        for segment in words(old: old.string, new: new.string) {
            let length = (segment.text as NSString).length
            switch segment.kind {
            case .equal:
                out.append(new.attributedSubstring(from: NSRange(location: newOffset, length: length)))
                oldOffset += length
                newOffset += length
            case .insert:
                let piece = NSMutableAttributedString(attributedString: new.attributedSubstring(from: NSRange(location: newOffset, length: length)))
                piece.addAttributes([.foregroundColor: Theme.NS.accent, .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: Theme.NS.accent],
                                    range: NSRange(location: 0, length: piece.length))
                out.append(piece)
                newOffset += length
            case .delete:
                let piece = NSMutableAttributedString(attributedString: old.attributedSubstring(from: NSRange(location: oldOffset, length: length)))
                piece.addAttributes([.foregroundColor: Theme.NS.mute, .strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: Theme.NS.mute],
                                    range: NSRange(location: 0, length: piece.length))
                out.append(piece)
                oldOffset += length
            }
        }
        return out
    }

    static func changedWordCount(_ segments: [Segment]) -> Int {
        segments.filter { $0.kind != .equal }.reduce(0) { $0 + tokens($1.text).count }
    }
}
