import AppKit
import Combine

struct EditablePoint: Identifiable {
    var id: String
    var label: String
    var done: Bool
}

/// State for one panel: the text, the checklist, and transient UI flags.
final class EditorModel: ObservableObject {
    let request: WriteRequest
    let editor = EditorHandle()

    @Published var text: NSAttributedString
    @Published var points: [EditablePoint]
    @Published var editingID: String?
    @Published var showSettings = false
    @Published var showDiff = false
    @Published var confirmation: Confirmation?

    enum Confirmation {
        case discard, sendEmpty

        var title: String {
            switch self {
            case .discard: return "Discard your edits?"
            case .sendEmpty: return "Send nothing back?"
            }
        }
        var detail: String {
            switch self {
            case .discard: return "The agent will be told you cancelled. A copy of what you wrote goes to history."
            case .sendEmpty: return "The text is empty, and the section you were handed was not. The agent will replace it with nothing."
            }
        }
        var confirm: String { self == .discard ? "Discard" : "Send empty" }
    }

    private let initialText: String

    init(request: WriteRequest) {
        let text = Markdown.attributed(from: request.draft)
        self.request = request
        self.text = text
        self.points = request.points.map { EditablePoint(id: $0.id, label: $0.label, done: false) }
        self.initialText = Markdown.export(text)
    }

    var isDirty: Bool {
        points.contains { $0.done } || !notes.isEmpty || Markdown.export(text) != initialText
    }

    /// Notes attached to runs of the text, in document order.
    var notes: [(quote: String, note: String, range: NSRange)] { Markdown.notes(in: text) }

    var doneCount: Int { points.filter { $0.done }.count }

    var hasDraft: Bool { !request.draft.isEmpty }

    /// Word-level changes against the draft, on the text as it reads (no Markdown syntax).
    var diff: [Diff.Segment] { Diff.words(old: Markdown.attributed(from: request.draft).string, new: text.string) }

    /// The same changes rendered with the editor's styling.
    var diffText: NSAttributedString { Diff.attributed(old: Markdown.attributed(from: request.draft), new: text) }

    var wordCount: Int {
        text.string.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// References Claude supplied, then links already used in the copy, deduped by URL.
    var links: [Reference] {
        var seen = Set<String>()
        var out: [Reference] = []
        for reference in request.references where seen.insert(reference.id).inserted {
            out.append(reference)
        }
        for link in Markdown.links(in: text) where seen.insert(link.url.absoluteString).inserted {
            out.append(Reference(label: link.label, url: link.url))
        }
        return out
    }

    func result() -> WriteResult {
        WriteResult(
            status: .sent,
            text: Markdown.export(text),
            points: points.map { WriteResult.PointState(id: $0.id, label: $0.label, done: $0.done) },
            notes: notes.map { WriteResult.Note(quote: $0.quote, note: $0.note) },
            asides: Markdown.asides(in: text.string)
        )
    }

    // MARK: Points

    func addPoint() {
        let id = "added-\(points.count + 1)"
        points.append(EditablePoint(id: id, label: "", done: false))
        editingID = id
    }

    func togglePoint(_ index: Int) {
        guard points.indices.contains(index) else { return }
        points[index].done.toggle()
    }

    /// Leaves edit mode; a point left blank is discarded.
    func commitEdit() {
        guard let id = editingID else { return }
        editingID = nil
        if let point = points.first(where: { $0.id == id }), point.label.trimmingCharacters(in: .whitespaces).isEmpty {
            points.removeAll { $0.id == id }
        }
    }

    func remove(_ id: String) {
        points.removeAll { $0.id == id }
        if editingID == id { editingID = nil }
    }

    func edit(_ id: String) {
        commitEdit()
        editingID = id
    }

    func movePoint(_ id: String, to index: Int) {
        guard let from = points.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(index, 0), points.count - 1)
        guard from != target else { return }
        let point = points.remove(at: from)
        points.insert(point, at: target)
    }

    // MARK: Links

    /// With text selected, links it. With nothing selected, opens the page instead of inserting anything.
    func useLink(_ reference: Reference) {
        guard let view = editor.view, view.selectedRange().length > 0 else {
            NSWorkspace.shared.open(reference.url)
            return
        }
        editor.focusThen { $0.applyLink(reference.url) }
    }

    func removeNote(at range: NSRange) {
        editor.focusThen { $0.removeNote(in: range) }
    }

    func select(_ range: NSRange) {
        editor.focusThen { view in
            view.setSelectedRange(range)
            view.scrollRangeToVisible(range)
            view.updateHoverBar()
        }
    }
}
