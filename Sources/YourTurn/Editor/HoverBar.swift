import AppKit

/// The formatting bar that floats above a selection. A borderless child window, so it is never
/// clipped by the editor and never takes the editor's focus. Mirrors the mymind tooltip: a light
/// capsule with a nib, which stretches into a URL field for links.
final class HoverBar: NSWindow, NSTextFieldDelegate, NSWindowDelegate {
    enum Mode { case buttons, link, note }

    static let height: CGFloat = 40
    static let nib: CGFloat = 5
    static let buttonNames = ["bold", "italic", "link", "note", "lookup"]
    static let barWidth: CGFloat = 6 + 36 * 5 + 6
    static let fieldWidth: CGFloat = 320

    private(set) var mode: Mode = .buttons
    var linkMode: Bool { mode == .link }
    var fieldMode: Bool { mode != .buttons }
    private weak var owner: RichTextView?
    private let background = HoverBarBackground()
    private let field = NSTextField()
    private var buttons: [String: NSButton] = [:]
    private var tiles: [String: NSView] = [:]

    init(owner: RichTextView) {
        self.owner = owner
        super.init(contentRect: NSRect(x: 0, y: 0, width: HoverBar.barWidth, height: HoverBar.height + HoverBar.nib),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = background
        delegate = self

        let keymap = Keymap.shared
        let specs: [(name: String, symbol: String, tip: String)] = [
            ("bold", "bold", "Bold  \(keymap.binding(.bold).display)"),
            ("italic", "italic", "Italic  \(keymap.binding(.italic).display)"),
            ("link", "link", "Link  \(keymap.binding(.link).display)"),
            ("note", "text.bubble", "Note about this  \(keymap.binding(.note).display)"),
            ("lookup", "character.book.closed", "Look Up  \(keymap.binding(.lookup).display)"),
        ]
        for spec in specs {
            let button = NSButton(image: NSImage(systemSymbolName: spec.symbol, accessibilityDescription: spec.tip)!,
                                  target: self, action: #selector(tapped(_:)))
            button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.identifier = NSUserInterfaceItemIdentifier(spec.name)
            button.toolTip = spec.tip
            button.setButtonType(.momentaryChange)
            let tile = NSView()
            tile.wantsLayer = true
            tile.layer?.cornerRadius = 8
            tiles[spec.name] = tile
            buttons[spec.name] = button
            background.addSubview(tile)
            background.addSubview(button)
        }

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Theme.nsFont(14)
        field.placeholderString = "Paste or type a link…"
        field.delegate = self
        field.isHidden = true
        background.addSubview(field)
        layout()
    }

    override var canBecomeKey: Bool { fieldMode }
    override var canBecomeMain: Bool { false }

    /// Active buttons get a tinted glyph and a soft tinted tile behind it.
    func setState(bold: Bool, italic: Bool, link: Bool, note: Bool) {
        let keymap = Keymap.shared
        for (name, active) in [("bold", bold), ("italic", italic), ("link", link), ("note", note), ("lookup", false)] {
            buttons[name]?.contentTintColor = active ? Theme.NS.accent : Theme.NS.barIcon
            tiles[name]?.layer?.backgroundColor = active ? Theme.NS.accent.withAlphaComponent(0.14).cgColor : nil
        }
        buttons["link"]?.toolTip = (link ? "Remove link  " : "Link  ") + keymap.binding(.link).display
        buttons["note"]?.toolTip = (note ? "Remove note  " : "Note about this  ") + keymap.binding(.note).display
    }

    /// Positions subviews for the current mode inside the current bounds; the window size is animated separately.
    private func layout() {
        let height = HoverBar.height
        if fieldMode {
            buttons.values.forEach { $0.isHidden = true }
            tiles.values.forEach { $0.isHidden = true }
            field.isHidden = false
            field.placeholderString = mode == .link ? "Paste or type a link…" : "Note about this…"
            field.frame = NSRect(x: 18, y: HoverBar.nib + (height - 20) / 2, width: background.bounds.width - 36, height: 20)
        } else {
            field.isHidden = true
            var x: CGFloat = 6
            for name in HoverBar.buttonNames {
                let frame = NSRect(x: x + 2, y: HoverBar.nib + 4, width: 32, height: 32)
                buttons[name]?.isHidden = false
                buttons[name]?.frame = frame
                tiles[name]?.isHidden = false
                tiles[name]?.frame = frame
                x += 36
            }
        }
        background.needsDisplay = true
    }

    @objc private func tapped(_ sender: NSButton) {
        switch sender.identifier?.rawValue {
        case "bold": owner?.toggleBold(nil)
        case "italic": owner?.toggleItalic(nil)
        case "link": owner?.insertLink(nil)
        case "note": owner?.insertNote(nil)
        case "lookup": owner?.lookUpSelection(nil)
        default: break
        }
    }

    // MARK: Field modes (link, note)

    private func frameKeepingCentre(width: CGFloat) -> NSRect {
        NSRect(x: round(frame.midX - width / 2), y: frame.minY, width: width, height: frame.height)
    }

    func enterLinkMode(prefill: String) { enter(.link, prefill: prefill) }
    func enterNoteMode(prefill: String) { enter(.note, prefill: prefill) }

    private func enter(_ newMode: Mode, prefill: String) {
        guard mode == .buttons else { return }
        mode = newMode
        field.stringValue = prefill
        buttons.values.forEach { $0.isHidden = true }
        tiles.values.forEach { $0.isHidden = true }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(self.frameKeepingCentre(width: HoverBar.fieldWidth), display: true)
        }, completionHandler: { [weak self] in
            guard let self = self, self.fieldMode else { return }
            self.layout()
            self.makeKeyAndOrderFront(nil)
            self.makeFirstResponder(self.field)
            self.field.currentEditor()?.selectAll(nil)
        })
    }

    func exitLinkMode() { exitFieldMode() }

    func exitFieldMode() {
        guard fieldMode else { return }
        mode = .buttons
        field.isHidden = true
        if let parent = owner?.window {
            parent.makeKeyAndOrderFront(nil)
            parent.makeFirstResponder(owner)
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            self.animator().setFrame(self.frameKeepingCentre(width: HoverBar.barWidth), display: true)
        }, completionHandler: { [weak self] in self?.layout() })
    }

    /// Clicking anywhere else while a field is open closes the bar.
    func windowDidResignKey(_ notification: Notification) {
        guard fieldMode else { return }
        mode = .buttons
        field.isHidden = true
        setFrame(frameKeepingCentre(width: HoverBar.barWidth), display: false)
        layout()
        owner?.hideHoverBar()
    }

    /// A pasted address commits straight away; no need to press Return.
    func controlTextDidChange(_ notification: Notification) {
        guard mode == .link else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let pasted = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty, value == pasted, URL.looksLikeWebAddress(value) else { return }
        owner?.commitLink(value)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if mode == .link { owner?.commitLink(field.stringValue) } else { owner?.commitNote(field.stringValue) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            exitFieldMode()
            owner?.updateHoverBar()
            return true
        default:
            return false
        }
    }
}

/// Capsule with a soft gradient, a hairline border and a nib underneath.
final class HoverBarBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let nib = HoverBar.nib
        let body = NSRect(x: 0.5, y: nib + 0.5, width: bounds.width - 1, height: bounds.height - nib - 1)
        let capsule = NSBezierPath(roundedRect: body, xRadius: body.height / 2, yRadius: body.height / 2)
        NSGradient(starting: Theme.NS.barTop, ending: Theme.NS.barBottom)?.draw(in: capsule, angle: -90)
        Theme.NS.barBorder.setStroke()
        capsule.lineWidth = 1
        capsule.stroke()

        let centre = bounds.midX
        let tip = NSBezierPath()
        tip.move(to: NSPoint(x: centre - 5, y: nib + 0.5))
        tip.line(to: NSPoint(x: centre, y: 0.5))
        tip.line(to: NSPoint(x: centre + 5, y: nib + 0.5))
        Theme.NS.barBottom.setFill()
        tip.fill()
        tip.lineWidth = 1
        Theme.NS.barBorder.setStroke()
        tip.stroke()
        Theme.NS.barBottom.setFill()
        NSRect(x: centre - 4.5, y: nib, width: 9, height: 1.5).fill()   // hide the seam
    }
}

extension URL {
    static func looksLikeWebAddress(_ string: String) -> Bool {
        guard let url = URL(string: string), let scheme = url.scheme else { return false }
        return ["http", "https", "mailto"].contains(scheme)
    }

    /// "optical.toys" → https://optical.toys; empty → nil.
    static func normalised(_ raw: String) -> URL? {
        var string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return nil }
        if !string.contains("://"), !string.hasPrefix("mailto:") { string = "https://" + string }
        return URL(string: string)
    }
}
