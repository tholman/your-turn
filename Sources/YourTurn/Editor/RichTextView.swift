import AppKit

/// Background tints (selection, notes, asides) hug the text instead of filling the stretched line box.
final class TextLayoutManager: NSLayoutManager {
    static func hugged(_ rect: NSRect, font: NSFont) -> NSRect {
        let height = ceil(font.ascender - font.descender) + 4
        guard height < rect.height else { return rect }
        return NSRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height)
    }

    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int, forCharacterRange charRange: NSRange, color: NSColor) {
        let font = (textStorage?.length ?? 0) > charRange.location
            ? (textStorage?.attribute(.font, at: charRange.location, effectiveRange: nil) as? NSFont) ?? TextStyle.font
            : TextStyle.font
        var hugged = (0..<rectCount).map { Self.hugged(rectArray[$0], font: font) }
        hugged.withUnsafeBufferPointer { buffer in
            super.fillBackgroundRectArray(buffer.baseAddress!, count: rectCount, forCharacterRange: charRange, color: color)
        }
    }
}

/// The editor: an NSTextView with bold, italic, links, lists, a paragraph model, and the hover bar.
final class RichTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?
    private var hoverBar: HoverBar?
    private var scrollObserver: NSObjectProtocol?

    static func make() -> RichTextView {
        // An explicit TextKit 1 stack gives predictable measurement for auto-height.
        let storage = NSTextStorage()
        let layout = TextLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let view = RichTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 40), textContainer: container)
        view.isRichText = true
        view.allowsUndo = true
        view.usesFontPanel = false
        view.usesRuler = false
        view.importsGraphics = false
        view.isAutomaticLinkDetectionEnabled = true
        view.isAutomaticQuoteSubstitutionEnabled = true
        view.isAutomaticDashSubstitutionEnabled = false   // two hyphens stay two hyphens; em dashes read as machine-written
        view.isContinuousSpellCheckingEnabled = true
        view.isGrammarCheckingEnabled = true
        view.isAutomaticSpellingCorrectionEnabled = true     // the system dictionary fixes typos as you type
        view.isAutomaticTextCompletionEnabled = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.autoresizingMask = []
        view.drawsBackground = false
        view.focusRingType = NSFocusRingType.none
        view.textContainerInset = NSSize(width: 0, height: 4)
        view.typingAttributes = TextStyle.typing
        view.font = TextStyle.font
        view.textColor = NSColor.textColor
        view.linkTextAttributes = [
            .foregroundColor: NSColor.labelColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: NSColor.tertiaryLabelColor,
            .cursor: NSCursor.pointingHand,
        ]
        view.selectedTextAttributes = [.backgroundColor: Theme.NS.highlight]
        view.insertionPointColor = NSColor.labelColor
        return view
    }

    // MARK: Sizing

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        textContainer?.size = NSSize(width: max(1, newSize.width - textContainerInset.width * 2), height: CGFloat.greatestFiniteMagnitude)
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        guard let container = textContainer, let layout = layoutManager else { return 40 }
        container.size = NSSize(width: max(1, width - textContainerInset.width * 2), height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return ceil(layout.usedRect(for: container).height) + textContainerInset.height * 2
    }

    // MARK: Focus and keys

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer = scrollObserver { NotificationCenter.default.removeObserver(observer) }
        scrollObserver = nil
        if let clip = enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                self?.hideHoverBar()
            }
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange?(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            onFocusChange?(false)
            if hoverBar?.fieldMode != true { hideHoverBar() }
        }
        return ok
    }

    /// Esc cancels the panel (or just the bar), ⌘↩ sends, ⇧↩ is a soft line break.
    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36
        if event.keyCode == 53 {
            if hoverBarVisible { hideHoverBar() } else { NSApp.sendAction(#selector(PanelController.cancelCopy(_:)), to: nil, from: self) }
        } else if isReturn, event.modifierFlags.contains(.command) {
            NSApp.sendAction(#selector(PanelController.sendCopy(_:)), to: nil, from: self)
        } else if isReturn, event.modifierFlags.contains(.shift) {
            insertLineBreak(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    /// The tracking loop for a drag-select runs inside mouseDown; when it returns the mouse is up.
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        updateHoverBar()
    }

    override func didChangeText() {
        super.didChangeText()
        highlightAsides()
        updateHoverBar()
    }

    /// {curly brace} asides get a teal tint. Temporary attributes: visual only, never exported.
    func highlightAsides() {
        guard let layout = layoutManager, let regex = try? NSRegularExpression(pattern: TextStyle.asidePattern) else { return }
        let whole = NSRange(location: 0, length: (string as NSString).length)
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
        layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
        for match in regex.matches(in: string, range: whole) {
            layout.addTemporaryAttributes([.foregroundColor: Theme.NS.asideInk, .backgroundColor: Theme.NS.asideTint], forCharacterRange: match.range)
        }
    }

    /// The caret is drawn at the font's height on the baseline, not the full (stretched) line box.
    static func insertionRect(for lineRect: NSRect, font: NSFont) -> NSRect {
        let height = ceil(font.ascender - font.descender) + 2
        guard height < lineRect.height else { return lineRect }
        return NSRect(x: lineRect.minX, y: lineRect.maxY - height, width: lineRect.width, height: height)
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let font = (typingAttributes[.font] as? NSFont) ?? TextStyle.font
        super.drawInsertionPoint(in: Self.insertionRect(for: rect, font: font), color: color, turnedOn: flag)
    }

    // MARK: Lists

    private var paragraphAtCaret: NSRange {
        (string as NSString).paragraphRange(for: NSRange(location: selectedRange().location, length: 0))
    }

    private func text(in range: NSRange) -> String { (string as NSString).substring(with: range) }

    private func setParagraphStyle(_ style: NSParagraphStyle, in range: NSRange) {
        textStorage?.addAttribute(.paragraphStyle, value: style, range: range)
        typingAttributes[.paragraphStyle] = style
    }

    private func colourMarker(at location: Int, length: Int) {
        textStorage?.addAttribute(.foregroundColor, value: Theme.NS.accent, range: NSRange(location: location, length: length))
        typingAttributes[.foregroundColor] = NSColor.textColor
    }

    /// Notes, links, bold and italic stop at the end of their run: typing right after one must not extend it.
    private func stopCarriedAttributes() {
        guard let storage = textStorage, selectedRange().length == 0 else { return }
        let caret = selectedRange().location
        func nextHas(_ key: NSAttributedString.Key) -> Bool {
            caret < storage.length && storage.attribute(key, at: caret, effectiveRange: nil) != nil
        }
        let fonts = NSFontManager.shared
        if let font = typingAttributes[.font] as? NSFont {
            let nextFont = caret < storage.length ? (storage.attribute(.font, at: caret, effectiveRange: nil) as? NSFont) : nil
            let nextTraits = nextFont.map { fonts.traits(of: $0) } ?? []
            var cleaned = font
            for trait in [NSFontTraitMask.boldFontMask, .italicFontMask] where fonts.traits(of: cleaned).contains(trait) && !nextTraits.contains(trait) {
                cleaned = fonts.convert(cleaned, toNotHaveTrait: trait)
            }
            if cleaned != font { typingAttributes[.font] = cleaned }
        }
        if typingAttributes[TextStyle.noteKey] != nil, !nextHas(TextStyle.noteKey) {
            typingAttributes[TextStyle.noteKey] = nil
            typingAttributes[.backgroundColor] = nil
            typingAttributes[.toolTip] = nil
        }
        if typingAttributes[.link] != nil, !nextHas(.link) {
            typingAttributes[.link] = nil
            typingAttributes[.toolTip] = nil
        }
    }

    /// "- ", "1. " or "## " typed at the start of an empty paragraph becomes a list item or heading.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        stopCarriedAttributes()
        super.insertText(string, replacementRange: replacementRange)
        guard let typed = string as? String, typed == " " else { return }
        let paragraph = paragraphAtCaret
        let content = text(in: paragraph)
        let caret = selectedRange().location
        if let heading = Markdown.heading(of: content), caret == paragraph.location + heading.level + 1 {
            let old = NSRange(location: paragraph.location, length: heading.level + 1)
            guard shouldChangeText(in: old, replacementString: "") else { return }
            textStorage?.replaceCharacters(in: old, with: "")
            textStorage?.addAttributes(TextStyle.headingAttributes(heading.level), range: paragraphAtCaret)
            typingAttributes = TextStyle.headingAttributes(heading.level)
            didChangeText()
            return
        }
        let kind: ListKind
        if caret == paragraph.location + 2, content.hasPrefix("- ") || content.hasPrefix("* ") {
            kind = .bullet
        } else if let range = content.range(of: "^\\d+\\. ", options: .regularExpression), caret == paragraph.location + content[range].utf16.count {
            kind = .number(Int(content[range].dropLast(2)) ?? 1)
        } else {
            return
        }
        let old = NSRange(location: paragraph.location, length: caret - paragraph.location)
        guard shouldChangeText(in: old, replacementString: kind.marker) else { return }
        // Keep whatever gap this paragraph already had above it, so the line stays put.
        let existing = (typingAttributes[.paragraphStyle] as? NSParagraphStyle) ?? TextStyle.paragraph
        let style = TextStyle.listParagraph.mutableCopy() as! NSMutableParagraphStyle
        style.paragraphSpacingBefore = existing.paragraphSpacingBefore
        textStorage?.replaceCharacters(in: old, with: NSAttributedString(string: kind.marker, attributes: typingAttributes))
        setParagraphStyle(style, in: paragraphAtCaret)
        colourMarker(at: paragraph.location, length: kind.marker.utf16.count - 1)
        didChangeText()
    }

    /// Return continues a list; Return on an empty item leaves it. Return after a heading starts body text.
    override func insertNewline(_ sender: Any?) {
        stopCarriedAttributes()
        let paragraph = paragraphAtCaret
        let content = text(in: paragraph)
        if typingAttributes[TextStyle.headingKey] != nil {
            super.insertNewline(sender)
            typingAttributes = TextStyle.typing
            textStorage?.removeAttribute(TextStyle.headingKey, range: paragraphAtCaret)
            setParagraphStyle(TextStyle.paragraph, in: paragraphAtCaret)
            return
        }
        guard let item = Lists.prefix(of: content) else {
            super.insertNewline(sender)
            setParagraphStyle(TextStyle.paragraph, in: paragraphAtCaret)
            return
        }
        if content.dropFirst(item.length).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            removeMarker(item.length, from: paragraph)
            return
        }
        super.insertNewline(sender)
        let start = selectedRange().location
        let marker = item.kind.next.marker
        super.insertText(marker, replacementRange: selectedRange())
        setParagraphStyle(TextStyle.listParagraph, in: paragraphAtCaret)   // tight under the item above
        colourMarker(at: start, length: marker.utf16.count - 1)
    }

    /// Backspace right after a marker removes the marker; on an empty heading it goes back to body text.
    override func deleteBackward(_ sender: Any?) {
        let paragraph = paragraphAtCaret
        let caret = selectedRange()
        if caret.length == 0, caret.location == paragraph.location, typingAttributes[TextStyle.headingKey] != nil {
            typingAttributes = TextStyle.typing
            textStorage?.removeAttribute(TextStyle.headingKey, range: paragraph)
            textStorage?.addAttributes([.font: TextStyle.font, .paragraphStyle: TextStyle.paragraph], range: paragraph)
            didChangeText()
            return
        }
        if caret.length == 0, let item = Lists.prefix(of: text(in: paragraph)), caret.location == paragraph.location + item.length {
            removeMarker(item.length, from: paragraph)
            return
        }
        super.deleteBackward(sender)
    }

    private func removeMarker(_ length: Int, from paragraph: NSRange) {
        let range = NSRange(location: paragraph.location, length: length)
        guard shouldChangeText(in: range, replacementString: "") else { return }
        textStorage?.replaceCharacters(in: range, with: "")
        setParagraphStyle(TextStyle.paragraph, in: paragraphAtCaret)
        didChangeText()
    }

    /// Colours that were baked in at creation; called when the theme changes.
    func applyTheme() {
        selectedTextAttributes = [.backgroundColor: Theme.NS.highlight]
        highlightAsides()
        needsDisplay = true
    }

    /// Re-fits every body font to the current text size; headings keep theirs.
    func applyTextSize() {
        guard let storage = textStorage else { return }
        let size = TextStyle.font.pointSize
        storage.beginEditing()
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, range, _ in
            guard attributes[TextStyle.headingKey] == nil, let font = attributes[.font] as? NSFont, font.pointSize != size else { return }
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toSize: size), range: range)
        }
        storage.endEditing()
        if typingAttributes[TextStyle.headingKey] == nil, let font = typingAttributes[.font] as? NSFont {
            typingAttributes[.font] = NSFontManager.shared.convert(font, toSize: size)
        }
        didChangeText()
    }

    // MARK: Formatting

    @objc func toggleBold(_ sender: Any?) { toggle(.boldFontMask) }
    @objc func toggleItalic(_ sender: Any?) { toggle(.italicFontMask) }

    private func toggle(_ trait: NSFontTraitMask) {
        let fonts = NSFontManager.shared
        func flipped(_ font: NSFont, on: Bool) -> NSFont {
            on ? fonts.convert(font, toHaveTrait: trait) : fonts.convert(font, toNotHaveTrait: trait)
        }
        let range = selectedRange()
        if range.length == 0 {
            let font = (typingAttributes[.font] as? NSFont) ?? TextStyle.font
            typingAttributes[.font] = flipped(font, on: !fonts.traits(of: font).contains(trait))
            return
        }
        guard let storage = textStorage else { return }
        var allHave = true
        storage.enumerateAttribute(.font, in: range) { value, _, stop in
            if !fonts.traits(of: (value as? NSFont) ?? TextStyle.font).contains(trait) { allHave = false; stop.pointee = true }
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            storage.addAttribute(.font, value: flipped((value as? NSFont) ?? TextStyle.font, on: !allHave), range: subrange)
        }
        storage.endEditing()
        didChangeText()
    }

    /// Links the selection to `url`; with no selection, inserts `text` (or the URL) as linked text at the caret.
    func applyLink(_ url: URL, text: String? = nil) {
        var target = selectedRange()
        if target.length == 0 {
            let inserted = (text?.isEmpty == false) ? text! : url.absoluteString
            insertText(inserted, replacementRange: target)
            target = NSRange(location: target.location, length: (inserted as NSString).length)
        }
        guard shouldChangeText(in: target, replacementString: nil) else { return }
        textStorage?.addAttribute(.link, value: url, range: target)
        textStorage?.addAttribute(.toolTip, value: url.absoluteString, range: target)
        didChangeText()
    }

    /// Link the selection (via the hover bar), remove an existing link, or with no selection ask for an address.
    @objc func insertLink(_ sender: Any?) {
        let range = selectedRange()
        if range.length > 0, let storage = textStorage,
           storage.attribute(.link, at: range.location, effectiveRange: nil) != nil,
           shouldChangeText(in: range, replacementString: nil) {
            storage.removeAttribute(.link, range: range)
            storage.removeAttribute(.toolTip, range: range)
            didChangeText()
            return
        }
        let pasted = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let prefill = URL.looksLikeWebAddress(pasted) ? pasted : ""
        if range.length > 0 {
            updateHoverBar()
            hoverBar?.enterLinkMode(prefill: prefill)
        } else {
            promptForLink(prefill: prefill, range: range)
        }
    }

    func commitLink(_ raw: String) {
        hoverBar?.exitFieldMode()
        if let url = URL.normalised(raw) { applyLink(url) }
        updateHoverBar()
    }

    // MARK: Notes attached to a run of text

    func applyNote(_ note: String) {
        let range = selectedRange()
        guard range.length > 0, shouldChangeText(in: range, replacementString: nil) else { return }
        textStorage?.addAttribute(TextStyle.noteKey, value: note, range: range)
        textStorage?.addAttribute(.backgroundColor, value: Theme.NS.noteTint, range: range)
        textStorage?.addAttribute(.toolTip, value: note, range: range)
        didChangeText()
    }

    func removeNote(in range: NSRange) {
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        textStorage?.removeAttribute(TextStyle.noteKey, range: range)
        textStorage?.removeAttribute(.backgroundColor, range: range)
        textStorage?.removeAttribute(.toolTip, range: range)
        didChangeText()
    }

    /// Note the selection via the hover bar, or remove an existing note under it.
    @objc func insertNote(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return }
        var noted = NSRange(location: NSNotFound, length: 0)
        if storage.attribute(TextStyle.noteKey, at: range.location, longestEffectiveRange: &noted, in: NSRange(location: 0, length: storage.length)) != nil {
            removeNote(in: noted)
            return
        }
        updateHoverBar()
        hoverBar?.enterNoteMode(prefill: "")
    }

    func commitNote(_ raw: String) {
        hoverBar?.exitFieldMode()
        let note = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { applyNote(note) }
        updateHoverBar()
    }

    private func promptForLink(prefill: String, range: NSRange) {
        guard let window = window else { return }
        let alert = NSAlert()
        alert.messageText = "Add Link"
        alert.informativeText = "The address will be inserted as text."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://"
        field.stringValue = prefill
        alert.accessoryView = field
        alert.addButton(withTitle: "Add Link")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn, let url = URL.normalised(field.stringValue) else { return }
            self.setSelectedRange(range)
            self.applyLink(url)
        }
    }

    /// The system Dictionary popover (with its Thesaurus tab) for the selection or the word at the caret.
    @objc func lookUpSelection(_ sender: Any?) {
        var range = selectedRange()
        if range.length == 0 {
            range = selectionRange(forProposedRange: range, granularity: .selectByWord)
            guard range.length > 0 else { return }
        }
        guard let storage = textStorage, let layout = layoutManager else { return }
        let word = storage.attributedSubstring(from: range)
        showDefinition(for: word, range: NSRange(location: 0, length: word.length), options: [:]) { [weak self] _ in
            guard let self = self else { return .zero }
            let glyph = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil).location
            let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let baseline = layout.location(forGlyphAt: glyph)
            return NSPoint(x: line.minX + baseline.x + self.textContainerOrigin.x, y: line.minY + baseline.y + self.textContainerOrigin.y)
        }
    }

    // MARK: Hover bar

    var hoverBarVisible: Bool { hoverBar?.isVisible ?? false }
    var hoverBarLinkMode: Bool { hoverBar?.linkMode ?? false }

    /// Screen rect of the first selected line, spanning the selection horizontally.
    private func selectionAnchor(_ range: NSRange) -> NSRect? {
        guard let layout = layoutManager, let container = textContainer, let window = window else { return nil }
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let bounds = layout.boundingRect(forGlyphRange: glyphs, in: container)
        let firstLine = layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let anchor = NSRect(x: bounds.minX + textContainerOrigin.x, y: firstLine.minY + textContainerOrigin.y,
                            width: bounds.width, height: firstLine.height)
        return window.convertToScreen(convert(anchor, to: nil))
    }

    func updateHoverBar() {
        if hoverBar?.fieldMode == true { return }
        let range = selectedRange()
        guard range.length > 0, let window = window, window.firstResponder === self, NSEvent.pressedMouseButtons == 0,
              let storage = textStorage, let anchor = selectionAnchor(range) else {
            hideHoverBar()
            return
        }
        let attributes = storage.attributes(at: range.location, effectiveRange: nil)
        let traits = NSFontManager.shared.traits(of: (attributes[.font] as? NSFont) ?? TextStyle.font)
        let bar = hoverBar ?? HoverBar(owner: self)
        hoverBar = bar
        bar.appearance = window.appearance
        bar.setState(bold: traits.contains(.boldFontMask), italic: traits.contains(.italicFontMask),
                     link: attributes[.link] != nil, note: attributes[TextStyle.noteKey] != nil)

        let size = NSSize(width: HoverBar.barWidth, height: HoverBar.height + HoverBar.nib)
        let x = min(max(anchor.midX - size.width / 2, window.frame.minX + 8), window.frame.maxX - size.width - 8)
        var y = anchor.maxY + 2
        if let screen = window.screen ?? NSScreen.main, y + size.height > screen.visibleFrame.maxY {
            y = anchor.minY - size.height - 2
        }
        let target = NSRect(x: round(x), y: round(y), width: size.width, height: size.height)

        if !bar.isVisible {
            bar.alphaValue = 0
            bar.setFrame(target.offsetBy(dx: 0, dy: -4), display: true)
            window.addChildWindow(bar, ordered: .above)
            bar.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                bar.animator().alphaValue = 1
                bar.animator().setFrame(target, display: true)
            }
        } else if abs(bar.frame.origin.y - target.origin.y) > 2 || abs(bar.frame.origin.x - target.origin.x) > 60 {
            // Another line or far away: fade out, reappear in the new spot.
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.08
                bar.animator().alphaValue = 0
            }, completionHandler: {
                guard bar.isVisible else { return }
                bar.setFrame(target, display: true)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.1
                    bar.animator().alphaValue = 1
                }
            })
        } else if abs(bar.frame.origin.x - target.origin.x) > 1 {
            // Same line, small shift (bold widened the word): glide.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                bar.animator().setFrame(target, display: true)
            }
        }
    }

    func hideHoverBar() {
        guard let bar = hoverBar, bar.isVisible else { return }
        if bar.fieldMode { bar.exitFieldMode() }
        window?.removeChildWindow(bar)
        bar.orderOut(nil)
    }

    /// For snapshots: the bar rendered, with its frame in the owning window's coordinates.
    func hoverBarSnapshot() -> (NSBitmapImageRep, NSRect)? {
        guard let bar = hoverBar, bar.isVisible, let view = bar.contentView, let window = window,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return (rep, window.convertFromScreen(bar.frame))
    }
}
