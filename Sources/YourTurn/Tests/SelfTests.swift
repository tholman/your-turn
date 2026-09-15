import AppKit

/// In-process self-tests: `your-turn --test`. No XCTest without Xcode, so this stays plain.
enum SelfTests {
    private static var failures: [String] = []
    private static var passed = 0

    private static func check(_ condition: Bool, _ name: String, line: Int = #line) {
        if condition { passed += 1 } else { failures.append("\(name)  (Tests.swift:\(line))") }
    }

    private static func isBold(_ text: NSAttributedString, at index: Int) -> Bool {
        let font = (text.attribute(.font, at: index, effectiveRange: nil) as? NSFont) ?? TextStyle.font
        return NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    }

    /// A text view in a real window, parked off-screen, so first-responder and child-window behaviour is exercised.
    private static func makeEditor(_ markdown: String) -> (NSWindow, RichTextView) {
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 600, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.orderFront(nil)
        let view = RichTextView.make()
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        view.textStorage?.setAttributedString(Markdown.attributed(from: markdown))
        view.highlightAsides()
        window.contentView = view
        window.makeFirstResponder(view)
        return (window, view)
    }

    private static func type(_ text: String, into view: RichTextView) {
        for character in text { view.insertText(String(character), replacementRange: view.selectedRange()) }
    }

    static func run() -> Int32 {
        markdown()
        formatting()
        lists()
        layoutStability()
        hoverBar()
        requests()
        model()
        keymap()
        links()
        server()
        headings()
        diffAndHistory()

        print("\(passed) passed, \(failures.count) failed")
        for failure in failures { print("  ✗ \(failure)") }
        return failures.isEmpty ? 0 : 1
    }

    private static func markdown() {
        let source = "**What:** Rotate *it* with [your mind](https://optical.toys/).\n\nSecond paragraph."
        let text = Markdown.attributed(from: source)
        check(isBold(text, at: 0), "import: bold applied to **What:**")
        check(!isBold(text, at: 8), "import: plain text not bold")
        check(text.attribute(.link, at: 26, effectiveRange: nil) != nil, "import: link attribute present")
        check(Markdown.export(text) == source, "round trip: export matches import (got: \(Markdown.export(text)))")
        check(Markdown.links(in: text).first?.url.absoluteString == "https://optical.toys/", "links(in:) finds the link")
        let typographic = "Dots… “quotes”, ‘singles’ and a non-breaking\u{00A0}space."
        check(Markdown.export(Markdown.attributed(from: typographic)) == typographic, "typography: ellipsis and curly quotes round trip")
        do {
            let (_, view) = makeEditor("")
            type("a -- b", into: view)
            check(!view.isAutomaticDashSubstitutionEnabled && view.string == "a -- b", "typography: two hyphens are never turned into an em dash")
        }

        check(Markdown.attributed(from: "a\n\nb").string == "a\nb", "paragraphs: blank line imports as one paragraph break")
        check(Markdown.export(Markdown.attributed(from: "a\n\nb")) == "a\n\nb", "paragraphs: blank line round trips")
        check(Markdown.attributed(from: "a\nb\n\nc").string == "a\u{2028}b\nc", "paragraphs: single newline imports as a soft break")
        check(Markdown.export(Markdown.attributed(from: "a\nb\n\nc")) == "a\nb\n\nc", "paragraphs: soft break round trips")
        check(Markdown.attributed(from: "- a\n- b\n\npara").string == "•\ta\n•\tb\npara", "paragraphs: bullets are their own paragraphs")
        check(Markdown.export(Markdown.attributed(from: "- a\n- b\n\npara")) == "- a\n- b\n\npara", "paragraphs: list then paragraph round trips")
        check(Markdown.export(NSAttributedString(string: "a\n\n\nb", attributes: TextStyle.typing)) == "a\n\nb", "paragraphs: empty paragraphs collapse")
        check(Markdown.attributed(from: "3. a\n4. b").string == "3.\ta\n4.\tb", "numbers: import keeps numbers")
        check(Markdown.export(Markdown.attributed(from: "1. a\n2. b\n\n- c")) == "1. a\n2. b\n\n- c", "numbers: list types separated by a blank line")
        let imported = Markdown.attributed(from: "- a\n- b\n\npara")
        let firstItem = imported.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let secondItem = imported.attribute(.paragraphStyle, at: 4, effectiveRange: nil) as? NSParagraphStyle
        let afterList = imported.attribute(.paragraphStyle, at: 8, effectiveRange: nil) as? NSParagraphStyle
        check(firstItem?.paragraphSpacingBefore == TextStyle.paragraphGap && secondItem?.paragraphSpacingBefore == TextStyle.listGap && afterList?.paragraphSpacingBefore == TextStyle.paragraphGap, "spacing: gap before the first item, tight between items, gap after the list")
        check(Markdown.asides(in: "hello {make this punchier} and {shorter} ok {}") == ["make this punchier", "shorter"], "asides: braces parsed, empty ignored")
        let dot = Markdown.attributed(from: "- a").attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        check(dot != nil && dot != NSColor.textColor, "bullets: marker is coloured")
    }

    private static func formatting() {
        do {
            let (_, view) = makeEditor("plain words here")
            view.setSelectedRange(NSRange(location: 0, length: 5))
            view.toggleBold(nil)
            check(isBold(view.attributedString(), at: 0), "toggleBold: selection becomes bold")
            check(!isBold(view.attributedString(), at: 7), "toggleBold: rest untouched")
            view.toggleBold(nil)
            check(!isBold(view.attributedString(), at: 0), "toggleBold: second toggle removes bold")
            check(Markdown.export(view.attributedString()) == "plain words here", "toggleBold: export clean after unbold")
            view.toggleBold(nil)
            view.setSelectedRange(NSRange(location: 5, length: 0))
            type("!", into: view)
            check(Markdown.export(view.attributedString()) == "**plain**! words here", "bold: typing after a bold run stays plain (got \(Markdown.export(view.attributedString())))")
            view.setSelectedRange(NSRange(location: 2, length: 0))
            type("?", into: view)
            check(Markdown.export(view.attributedString()) == "**pl?ain**! words here", "bold: typing inside a bold run stays bold")
        }
        do {
            // A click on the hover bar must never break formatting even if focus moved.
            let (window, view) = makeEditor("plain words here")
            view.setSelectedRange(NSRange(location: 6, length: 5))
            window.makeFirstResponder(nil)
            view.toggleBold(nil)
            check(Markdown.export(view.attributedString()) == "plain **words** here", "toggleBold: works without first responder")
        }
        do {
            let (_, view) = makeEditor("plain words here")
            view.setSelectedRange(NSRange(location: 0, length: 5))
            view.toggleBold(nil)
            view.toggleItalic(nil)
            check(Markdown.export(view.attributedString()) == "***plain*** words here", "bold+italic export (got: \(Markdown.export(view.attributedString())))")
        }
        do {
            let (_, view) = makeEditor("see the duck")
            view.setSelectedRange(NSRange(location: 8, length: 4))
            view.applyLink(URL(string: "https://optical.toys/spinning-duck/")!)
            check(Markdown.export(view.attributedString()) == "see the [duck](https://optical.toys/spinning-duck/)", "applyLink: exported as a markdown link")
            view.setSelectedRange(NSRange(location: 8, length: 4))
            view.insertLink(nil)
            check(Markdown.export(view.attributedString()) == "see the duck", "insertLink on a link removes it")
            view.setSelectedRange(NSRange(location: 12, length: 0))
            view.applyLink(URL(string: "https://x.y/")!, text: "Duck")
            check(view.string == "see the duckDuck", "applyLink with no selection inserts the label")
        }
        check(URL.normalised("optical.toys")?.absoluteString == "https://optical.toys", "normalised: bare domain gets https://")
        check(URL.normalised("  ") == nil, "normalised: blank is nil")
        check(URL.looksLikeWebAddress("https://a.b") && !URL.looksLikeWebAddress("hello"), "looksLikeWebAddress")
    }

    private static func firstLineTop(_ view: RichTextView) -> CGFloat {
        view.layoutManager!.ensureLayout(for: view.textContainer!)
        return view.layoutManager!.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minY
    }

    private static func layoutStability() {
        do {
            let (_, view) = makeEditor("")
            type("Dont", into: view)
            let before = firstLineTop(view)
            let heightBefore = view.layoutManager!.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height
            view.insertNewline(nil)
            check(firstLineTop(view) == before, "layout: Return does not move the line above (\(before) → \(firstLineTop(view)))")
            check(view.layoutManager!.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height == heightBefore, "layout: Return does not change the height of the line above")
            type("next", into: view)
            check(firstLineTop(view) == before, "layout: typing on the new line does not move the line above")
        }
        do {
            let (_, view) = makeEditor("")
            type("1. cool dogs", into: view)
            view.insertNewline(nil)
            view.insertNewline(nil)          // leave the list: this paragraph carries the gap
            func caretTop() -> CGFloat {
                view.layoutManager!.ensureLayout(for: view.textContainer!)
                return view.firstRect(forCharacterRange: view.selectedRange(), actualRange: nil).origin.y
            }
            let paragraphTop = caretTop()
            type("- ", into: view)
            check(abs(caretTop() - paragraphTop) < 0.5, "layout: a bullet after a numbered list does not jump (\(paragraphTop) → \(caretTop()))")
        }
    }

    private static func lists() {
        do {
            let (_, view) = makeEditor("")
            type("- ", into: view)
            check(view.string == "•\t", "bullets: '- ' converts (got '\(view.string)')")
            type("first", into: view)
            view.insertNewline(nil)
            check(view.string == "•\tfirst\n•\t", "bullets: Return continues the list (got '\(view.string)')")
            type("second", into: view)
            view.insertNewline(nil)
            view.insertNewline(nil)
            check(view.string == "•\tfirst\n•\tsecond\n", "bullets: Return on an empty item leaves the list (got '\(view.string)')")
        check((view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.paragraphSpacingBefore == TextStyle.paragraphGap, "bullets: leaving a list restores the paragraph gap")
            check(Markdown.export(view.attributedString()) == "- first\n- second", "bullets: export as a markdown list")
            let style = view.attributedString().attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            check(style?.headIndent == TextStyle.listIndent, "bullets: hanging indent applied")
        }
        do {
            let (_, view) = makeEditor("")
            type("1. one", into: view)
            check(view.string == "1.\tone", "numbers: '1. ' converts (got '\(view.string)')")
            view.insertNewline(nil)
            check(view.string == "1.\tone\n2.\t", "numbers: Return continues with 2. (got '\(view.string)')")
            type("two", into: view)
            view.insertNewline(nil)
            view.insertNewline(nil)
            check(Markdown.export(view.attributedString()) == "1. one\n2. two", "numbers: export (got '\(Markdown.export(view.attributedString()))')")
        }
        do {
            let (_, view) = makeEditor("")
            type("1. ", into: view)
            view.deleteBackward(nil)
            check(view.string == "", "lists: backspace right after a marker removes it")
            view.insertText("- ", replacementRange: view.selectedRange())   // pasted in one go: not a list
            check(view.string == "- ", "lists: a pasted '- ' is left alone")
        }
    }

    private static func hoverBar() {
        let (window, view) = makeEditor("plain words here")
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 0, length: 5))
        view.updateHoverBar()
        check(view.hoverBarVisible, "hover bar: visible with a selection")
        view.insertLink(nil)
        check(view.hoverBarLinkMode, "hover bar: link mode entered from insertLink with a selection")
        view.commitLink("optical.toys")
        check(!view.hoverBarLinkMode, "hover bar: commit leaves link mode")
        check(Markdown.export(view.attributedString()) == "[plain](https://optical.toys) words here", "hover bar: committed link exported (got \(Markdown.export(view.attributedString())))")
        view.setSelectedRange(NSRange(location: 6, length: 5))
        view.insertNote(nil)
        view.commitNote("  rethink this word  ")
        let notes = Markdown.notes(in: view.attributedString())
        check(notes.count == 1 && notes[0].quote == "words" && notes[0].note == "rethink this word", "notes: attached to the selection and trimmed (got \(notes))")
        check(!Markdown.export(view.attributedString()).contains("rethink"), "notes: never leak into the copy")
        view.setSelectedRange(NSRange(location: 11, length: 0))
        type("!", into: view)
        check(Markdown.notes(in: view.attributedString()).first?.quote == "words", "notes: typing after a note does not extend it")
        view.setSelectedRange(NSRange(location: 5, length: 0))
        type("!", into: view)
        check(Markdown.export(view.attributedString()).hasPrefix("[plain](https://optical.toys)!"), "links: typing after a link does not extend it (got \(Markdown.export(view.attributedString())))")
        view.setSelectedRange(NSRange(location: 8, length: 2))
        view.insertNote(nil)
        check(Markdown.notes(in: view.attributedString()).isEmpty, "notes: insertNote on a noted range removes the whole note")
        view.setSelectedRange(NSRange(location: 5, length: 0))
        view.updateHoverBar()
        check(!view.hoverBarVisible, "hover bar: hidden when the selection collapses")
    }

    private static func requests() {
        check((try? WriteRequest.parse(["points": []])) == nil, "parse: title required")
        let request = try? WriteRequest.parse([
            "title": "Tetrachord", "draft": "**x**",
            "points": [["label": "A"], ["id": "b", "label": "B"], ["nope": "no label"]],
            "references": [["label": "Duck", "url": "https://optical.toys/spinning-duck/"], ["url": "not a url at all"]],
        ])
        check(request?.points.count == 2, "parse: unlabeled points dropped")
        check(request?.points[0].id == "point-1" && request?.points[1].id == "b", "parse: ids default or keep")
        check(request?.references.count == 1, "parse: junk reference dropped, good one kept")
    }

    private static func model() {
        let request = try! WriteRequest.parse(["title": "T", "draft": "Hello *there*", "points": [["label": "A"], ["label": "B"]]])
        let model = EditorModel(request: request)
        check(!model.isDirty, "model: clean at start")
        model.points[0].done = true
        let result = model.result()
        check(result.text == "Hello *there*", "model: result text is markdown")
        check(result.points.map { $0.done } == [true, false], "model: done flags carried")
        check(model.isDirty, "model: dirty after ticking")
        check(result.summary().contains("- [x] A") && result.summary().contains("- [ ] B"), "result: summary checklist")
        model.addPoint()
        check(model.editingID == model.points.last?.id, "model: addPoint enters edit mode")
        model.commitEdit()
        check(model.points.count == 2, "model: empty new point discarded on commit")
        model.togglePoint(1)
        model.togglePoint(5)
        check(model.points.map { $0.done } == [true, true], "model: togglePoint by index, out of range ignored")
        model.movePoint(model.points[1].id, to: 0)
        check(model.points.map { $0.label } == ["B", "A"], "model: movePoint reorders")
        model.movePoint("nope", to: 0)
        model.movePoint(model.points[0].id, to: 99)
        check(model.points.map { $0.label } == ["A", "B"], "model: movePoint clamps and ignores unknown ids")
        model.edit(model.points[0].id)
        check(model.editingID == model.points[0].id, "model: edit opens the label")
        check((model.result().json()["notes"] as? [[String: Any]])?.isEmpty == true, "model: notes array present when empty")
        do {
            let (_, view) = makeEditor("see the duck")
            let noted = EditorModel(request: try! WriteRequest.parse(["title": "T", "draft": "see the duck"]))
            noted.editor.view = view
            view.setSelectedRange(NSRange(location: 8, length: 4))
            view.applyNote("which duck?")
            noted.text = view.attributedString()
            check(noted.notes.count == 1, "notes: model lists the attached note")
            noted.removeNote(at: noted.notes[0].range)
            noted.text = view.attributedString()
            check(noted.notes.isEmpty, "notes: removable from the model")
        }
        let asideModel = EditorModel(request: try! WriteRequest.parse(["title": "T", "draft": "Keep {this one short} please"]))
        check(asideModel.result().asides == ["this one short"] && asideModel.result().summary().contains("curly braces"), "model: asides reported and explained")
        let (_, asideView) = makeEditor("Keep {this one short} please")
        check(asideView.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 6, effectiveRange: nil) != nil, "asides: highlighted in the editor")
        check(asideView.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 1, effectiveRange: nil) == nil, "asides: plain text not highlighted")
        let tall = NSRect(x: 0, y: 0, width: 80, height: 30)
        let hug = TextLayoutManager.hugged(tall, font: TextStyle.font)
        check(hug.maxY == tall.maxY && hug.height < tall.height, "tints: hug the text at the bottom of the line box (got \(hug))")
        let line = NSRect(x: 10, y: 100, width: 1, height: 30)
        let caret = RichTextView.insertionRect(for: line, font: TextStyle.font)
        check(caret.maxY == line.maxY && caret.height < line.height && caret.height > 16, "caret: font-height on the baseline, not the full line box (got \(caret))")
    }

    private static func headings() {
        let text = Markdown.attributed(from: "## Changelog\n\n- Initial release\n\nBody **bold** here")
        check(text.attribute(TextStyle.headingKey, at: 0, effectiveRange: nil) as? Int == 2, "headings: ## imports as level 2")
        check((text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName.hasPrefix("Charter") == true, "headings: serif face")
        check(Markdown.export(text) == "## Changelog\n\n- Initial release\n\nBody **bold** here", "headings: round trip (got \(Markdown.export(text)))")
        do {
            let (_, view) = makeEditor("")
            type("## Title", into: view)
            check(view.attributedString().attribute(TextStyle.headingKey, at: 0, effectiveRange: nil) as? Int == 2, "headings: typing '## ' converts")
            check(view.string == "Title", "headings: marker removed from the text (got '\(view.string)')")
            view.insertNewline(nil)
            type("body", into: view)
            check(view.attributedString().attribute(TextStyle.headingKey, at: 6, effectiveRange: nil) == nil, "headings: Return starts body text")
            check(Markdown.export(view.attributedString()) == "## Title\n\nbody", "headings: typed heading exports (got \(Markdown.export(view.attributedString())))")
        }
        do {
            let (_, view) = makeEditor("# Big\n\ntext")
            view.setSelectedRange(NSRange(location: 0, length: 0))
            view.deleteBackward(nil)
            check(view.attributedString().attribute(TextStyle.headingKey, at: 0, effectiveRange: nil) == nil, "headings: backspace at the start makes it body text")
        }
    }

    private static func diffAndHistory() {
        let segments = Diff.words(old: "the quick brown fox", new: "the slow brown fox jumps")
        check(segments == [
            Diff.Segment(kind: .equal, text: "the "), Diff.Segment(kind: .delete, text: "quick "), Diff.Segment(kind: .insert, text: "slow "),
            Diff.Segment(kind: .equal, text: "brown fox "), Diff.Segment(kind: .insert, text: "jumps"),
        ], "diff: word-level insert and delete (got \(segments))")
        check(Diff.words(old: "same", new: "same") == [Diff.Segment(kind: .equal, text: "same")], "diff: identical text is one equal run")
        let model = EditorModel(request: try! WriteRequest.parse(["title": "T", "draft": "one two"]))
        check(model.hasDraft && model.diff.allSatisfy { $0.kind == .equal }, "diff: untouched draft has no changes")
        let styled = Diff.attributed(old: Markdown.attributed(from: "## Title\n\n- keep\n- drop this"), new: Markdown.attributed(from: "## Title\n\n- keep\n- add that"))
        check(styled.attribute(TextStyle.headingKey, at: 0, effectiveRange: nil) as? Int == 2, "diff: styled diff keeps the heading")
        let struck = (styled.string as NSString).range(of: "drop")
        check(styled.attribute(.strikethroughStyle, at: struck.location, effectiveRange: nil) != nil, "diff: deletions struck in place")
        let added = (styled.string as NSString).range(of: "add")
        check(styled.attribute(.underlineStyle, at: added.location, effectiveRange: nil) != nil, "diff: insertions underlined")

        let scratch = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("your-turn-history-test.jsonl")
        try? FileManager.default.removeItem(at: scratch)
        History.record(title: "A", result: WriteResult(status: .sent, text: "first line\nmore", points: []), to: scratch)
        History.record(title: "B", result: .cancelled, to: scratch)
        let entries = History.entries(from: scratch)
        check(entries.count == 2 && entries[0]["title"] as? String == "A" && entries[1]["status"] as? String == "cancelled", "history: appends one JSON line per result")
        check(History.summary(count: 1, from: scratch).contains("B"), "history: summary shows newest first")

        let settings = Settings(defaults: UserDefaults(suiteName: "your-turn.tests")!)
        settings.theme = .paper
        check(Settings(defaults: UserDefaults(suiteName: "your-turn.tests")!).theme == .paper, "settings: persist")
        settings.theme = .system
    }

    private static func keymap() {
        check(KeyBinding.parse("cmd+shift+n") == KeyBinding(key: "n", mods: [.command, .shift]), "keymap: parses cmd+shift+n")
        check(KeyBinding.parse("cmd+return")?.display == "⌘↩", "keymap: display of return")
        check(KeyBinding.parse("cmd+return")?.source == "cmd+return", "keymap: source round trip")
        check(KeyBinding.parse("cmd+banana") == nil, "keymap: junk rejected")
        let keymap = Keymap()
        let item = NSMenuItem(title: "Send", action: nil, keyEquivalent: "")
        keymap.register(item, for: .send)
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("your-turn-keys-test.json")
        keymap.save(to: scratch)
        let reloaded = Keymap()
        reloaded.load(from: scratch)
        check(reloaded.binding(.send) == keymap.binding(.send), "keymap: save then load round trips")
        check(item.keyEquivalent == "\r" && item.keyEquivalentModifierMask == [.command], "keymap: default applied to a menu item")
        keymap.apply(overrides: ["send": "cmd+shift+return", "bold": "nonsense"])
        check(item.keyEquivalent == "\r" && item.keyEquivalentModifierMask == [.command, .shift], "keymap: override re-applies to the menu item")
        check(keymap.binding(.bold) == Keymap.defaults[.bold], "keymap: bad override keeps the default")
    }

    private static func links() {
        let html = "<html><head><TITLE> Spinning &amp; Dancing  \n Dots </TITLE></head></html>".data(using: .utf8)!
        check(LinkInfo.parseTitle(html) == "Spinning & Dancing Dots", "links: title parsed and entities decoded")
        check(LinkInfo.parseTitle("no title here".data(using: .utf8)!) == nil, "links: no title → nil")
    }

    private static func server() {
        var replies: [[String: Any]] = []
        let server = MCPServer(present: { _, done in done(WriteResult(status: .sent, text: "hi **there**", points: [])) })
        server.output = { data in
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { replies.append(object) }
        }
        server.handle(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18"]])
        server.handle(["jsonrpc": "2.0", "method": "notifications/initialized"])
        server.handle(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        server.handle(["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": MCPServer.toolName, "arguments": ["points": []]]])
        server.handle(["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": MCPServer.toolName, "arguments": ["title": "T"]]])
        server.handle(["jsonrpc": "2.0", "id": 5, "method": "nope"])
        check(replies.count == 5, "mcp: one reply per request, none for notifications (got \(replies.count))")
        check((replies[0]["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-06-18", "mcp: echoes a known protocol version")
        let tools = (replies[1]["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        check(tools?.first?["name"] as? String == MCPServer.toolName, "mcp: tools/list exposes the tool")
        check((replies[2]["result"] as? [String: Any])?["isError"] as? Bool == true, "mcp: bad arguments → isError")
        let structured = (replies[3]["result"] as? [String: Any])?["structuredContent"] as? [String: Any]
        check(structured?["text"] as? String == "hi **there**", "mcp: tools/call returns the copy")
        check((replies[4]["error"] as? [String: Any])?["code"] as? Int == -32601, "mcp: unknown method → -32601")
    }
}
