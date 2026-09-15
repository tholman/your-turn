import AppKit

/// Serialises panel presentation so overlapping tool calls queue instead of stacking,
/// and puts the app in the Dock only while a panel is up.
final class PanelQueue {
    /// Render modes: the window is placed off-screen and never activated, so it cannot steal the keyboard.
    var quiet = false

    private var pending: [(WriteRequest, (WriteResult) -> Void)] = []
    private(set) var current: PanelController?

    func present(_ request: WriteRequest, completion: @escaping (WriteResult) -> Void) {
        pending.append((request, completion))
        pump()
    }

    private func pump() {
        guard current == nil else { return }
        guard !pending.isEmpty else {
            NSApp.setActivationPolicy(.accessory)
            return
        }
        let (request, completion) = pending.removeFirst()
        let controller = PanelController(request: request) { [weak self] result in
            self?.current = nil
            completion(result)
            self?.pump()
        }
        current = controller
        if quiet {
            controller.showQuietly()
        } else {
            NSApp.applicationIconImage = DockIcon.image()
            NSApp.setActivationPolicy(.regular)
            controller.show()
        }
    }
}

/// The mark: two dots, ink then teal. The baton passes to you.
enum DockIcon {
    static func draw(in rect: NSRect, tile: Bool) {
        if tile {
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.08, dy: rect.width * 0.08),
                                    xRadius: rect.width * 0.2, yRadius: rect.width * 0.2)
            NSColor.white.setFill()
            path.fill()
            NSColor(hex: 0xE3E1DC).setStroke()
            path.lineWidth = max(1, rect.width * 0.012)
            path.stroke()
        }
        let d = rect.width * 0.2, gap = rect.width * 0.08
        let y = rect.midY - d / 2
        NSColor(hex: 0x1A1918).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.midX - gap / 2 - d, y: y, width: d, height: d)).fill()
        NSColor(hex: 0x14A38F).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.midX + gap / 2, y: y, width: d, height: d)).fill()
    }

    static func image(size: CGFloat = 512) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect, tile: true)
            return true
        }
    }

    /// Writes an .iconset folder for `iconutil`.
    static func writeIconset(to directory: String) throws {
        let folder = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = base * scale
                let image = image(size: CGFloat(pixels))
                guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { continue }
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try png.write(to: folder.appendingPathComponent(name))
            }
        }
    }
}
