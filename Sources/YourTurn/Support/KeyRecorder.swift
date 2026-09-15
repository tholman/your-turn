import AppKit
import SwiftUI

/// Shows a key binding; click it and press the new keys to change it. Esc keeps the old one.
struct KeyRecorder: NSViewRepresentable {
    var binding: KeyBinding
    var onChange: (KeyBinding) -> Void

    func makeNSView(context: Context) -> KeyRecorderView {
        let view = KeyRecorderView()
        view.binding = binding
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: KeyRecorderView, context: Context) {
        view.binding = binding
        view.onChange = onChange
    }
}

final class KeyRecorderView: NSView {
    var binding = KeyBinding(key: "", mods: []) { didSet { needsDisplay = true } }
    var onChange: ((KeyBinding) -> Void)?
    private var recording = false { didSet { needsDisplay = true } }
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        recording = true
        // Swallow the key press before the window sees it, so recording ⌘↩ never also sends.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.recording, event.window === self.window else { return event }
            self.record(event)
            return nil
        }
        return true
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        return true
    }

    override func keyDown(with event: NSEvent) { record(event) }

    private func record(_ event: NSEvent) {
        defer { window?.makeFirstResponder(nil) }
        guard event.keyCode != 53 else { return }   // Esc keeps the old binding
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key: String
        if event.keyCode == 36 {
            key = "\r"
        } else if let characters = event.charactersIgnoringModifiers?.lowercased(), let first = characters.first,
                  first.isLetter || first.isNumber || "/.,;'[]-=`".contains(first) {
            key = String(first)
        } else {
            return
        }
        guard !mods.isEmpty || key == "\r" else { return }   // a bare letter would swallow typing
        let newBinding = KeyBinding(key: key, mods: mods)
        binding = newBinding
        onChange?(newBinding)
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (recording ? Theme.NS.accent.withAlphaComponent(0.12) : NSColor.clear).setFill()
        box.fill()
        (recording ? Theme.NS.accent : Theme.NS.hairline).setStroke()
        box.stroke()
        let label = recording ? "press keys…" : binding.display
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: recording ? "AvenirNext-Regular" : "AvenirNext-DemiBold", size: 11) ?? NSFont.systemFont(ofSize: 11),
            .foregroundColor: recording ? Theme.NS.accent : Theme.NS.ink,
        ]
        let size = (label as NSString).size(withAttributes: attributes)
        (label as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }
}
