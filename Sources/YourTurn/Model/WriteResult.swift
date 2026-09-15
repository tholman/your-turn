import Foundation

/// What comes back to Claude.
struct WriteResult {
    enum Status: String { case sent, cancelled }

    struct PointState {
        var id: String
        var label: String
        var done: Bool
    }

    struct Note {
        var quote: String
        var note: String
    }

    var status: Status
    var text: String          // Markdown
    var points: [PointState]
    var notes: [Note] = []    // notes attached to specific runs of the text
    var asides: [String] = [] // {curly brace} asides written inline

    static let cancelled = WriteResult(status: .cancelled, text: "", points: [])

    /// A readable version for the model's context window.
    func summary() -> String {
        guard status == .sent else {
            return "Status: cancelled\nThe human dismissed the panel without sending. Do not assume any copy was written.\n"
        }
        var out = "Status: sent\n\nCopy (Markdown):\n"
        out += text.isEmpty ? "(empty)\n" : text + "\n"
        if !points.isEmpty {
            out += "\nPoints:\n"
            for point in points {
                out += "- [\(point.done ? "x" : " ")] \(point.label)"
                out += point.done ? "\n" : "  (not ticked; the human may have skipped it on purpose)\n"
            }
        }
        if !asides.isEmpty {
            out += "\nAsides in {curly braces} are instructions to you, not copy. Strip them before using the text:\n"
            for aside in asides { out += "- \(aside)\n" }
        }
        if !notes.isEmpty {
            out += "\nNotes the human attached to runs of the text:\n"
            for note in notes { out += "- “\(note.quote)”: \(note.note)\n" }
        }
        return out
    }

    func json() -> [String: Any] {
        [
            "status": status.rawValue,
            "text": text,
            "asides": asides,
            "notes": notes.map { ["quote": $0.quote, "note": $0.note] as [String: Any] },
            "points": points.map { ["id": $0.id, "label": $0.label, "done": $0.done] as [String: Any] },
        ]
    }

    func jsonString() -> String {
        let data = (try? JSONSerialization.data(withJSONObject: json(), options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
