import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Renders the panel to a PNG without screen-recording permission. Development aid for --demo/--file.
enum Snapshot {
    /// After a second: a plain render; then with the first words selected so the hover bar shows.
    static func schedule(_ panels: PanelQueue, to path: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { write(panels.current, to: path) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard let controller = panels.current, let view = controller.model.editor.view else { return }
            controller.window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: 0, length: min(9, view.string.count)))
            view.updateHoverBar()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                write(controller, to: path.replacingOccurrences(of: ".png", with: "-selection.png"))
            }
        }
    }

    /// Called by the demo runner just before it exits, so a recording can be written first.
    static var onFinish: (() -> Void)?

    /// Records a scripted run as a GIF: the window easing in, a selection and the hover bar, typing,
    /// a tick, settings and the paper theme, then Send. Frames are the framed composite at 1x.
    static func gif(_ panels: PanelQueue, to path: String) {
        let fps = 15.0
        var frames: [CGImage] = []
        var lastFrame: NSSize = .zero
        let timer = Timer(timeInterval: 1 / fps, repeats: true) { _ in
            guard let controller = panels.current else { return }
            let frame = controller.window.frame
            if lastFrame == .zero { lastFrame = frame.size }
            if let image = framedFrame(controller, restingSize: lastFrame) {
                frames.append(image)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        func at(_ seconds: Double, _ work: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work) }
        var typing = ""
        at(1.0) {
            guard let controller = panels.current, let view = controller.model.editor.view else { return }
            controller.window.makeFirstResponder(view)
            view.setSelectedRange((view.string as NSString).range(of: "terrible at sounding like you"))
            view.updateHoverBar()
        }
        at(1.9) { panels.current?.model.editor.view?.toggleBold(nil) }
        at(2.6) {
            guard let view = panels.current?.model.editor.view else { return }
            view.hideHoverBar()
            view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
            typing = " Any MCP client can call it."
        }
        let typeTimer = Timer(timeInterval: 0.045, repeats: true) { _ in
            guard !typing.isEmpty, let view = panels.current?.model.editor.view else { return }
            let character = String(typing.removeFirst())
            view.insertText(character, replacementRange: view.selectedRange())
        }
        RunLoop.main.add(typeTimer, forMode: .common)
        at(5.2) { panels.current?.model.points[1].done = true }
        at(6.0) { panels.current?.model.showSettings = true }
        at(7.2) { Settings.shared.theme = .paper }
        at(8.6) { panels.current?.model.showSettings = false }
        at(9.6) { panels.current?.sendCopy(nil) }
        onFinish = {
            timer.invalidate()
            typeTimer.invalidate()
            Settings.shared.theme = .system     // the recording must not leave a preference behind
            writeGIF(frames, fps: fps, to: path)
        }
    }

    /// One frame: the window as it currently is (size and alpha follow its animations) on the ambient background.
    private static func framedFrame(_ controller: PanelController, restingSize: NSSize) -> CGImage? {
        guard let view = controller.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let window = NSImage(size: view.bounds.size)
        window.addRepresentation(rep)
        if let (barRep, frame) = controller.model.editor.view?.hoverBarSnapshot() {
            let bar = NSImage(size: frame.size)
            bar.addRepresentation(barRep)
            window.lockFocus()
            bar.draw(in: frame)
            window.unlockFocus()
        }
        var scaled = window
        var lift: CGFloat = 0
        if let presentation = view.layer?.presentation() {
            let transform = presentation.transform
            let factor = transform.m11
            lift = transform.m42
            if abs(factor - 1) > 0.001 {
                scaled = NSImage(size: NSSize(width: window.size.width * factor, height: window.size.height * factor))
                scaled.lockFocus()
                window.draw(in: NSRect(origin: .zero, size: scaled.size), from: NSRect(origin: .zero, size: window.size), operation: .sourceOver, fraction: 1)
                scaled.unlockFocus()
            }
        }
        let image = framed(scaled, restingSize: restingSize, alpha: controller.window.alphaValue, scale: 1, lift: lift)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func writeGIF(_ frames: [CGImage], fps: Double, to path: String) {
        guard !frames.isEmpty,
              let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
        for frame in frames { CGImageDestinationAddImage(destination, frame, frameProperties) }
        CGImageDestinationFinalize(destination)
    }

    /// Renders the states worth showing in the README: writing, hover bar, settings, changes. Then exits.
    static func screenshots(_ panels: PanelQueue, to directory: String) {
        let folder = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func at(_ seconds: Double, _ work: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work) }
        func shot(_ name: String) { write(panels.current, to: folder.appendingPathComponent(name).path, styled: true) }
        at(1.0) {
            guard let controller = panels.current, let view = controller.model.editor.view else { return }
            controller.window.makeFirstResponder(view)
            let word = (view.string as NSString).range(of: "terrible")
            view.setSelectedRange(word)
            view.applyNote("softer word?")
            view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
            controller.model.points[0].done = true
        }
        at(1.4) { shot("writing.png") }
        at(1.7) {
            guard let controller = panels.current, let view = controller.model.editor.view else { return }
            view.setSelectedRange((view.string as NSString).range(of: "sounding like you"))
            view.updateHoverBar()
        }
        at(2.1) { shot("hover-bar.png") }
        at(2.3) {
            guard let controller = panels.current, let view = controller.model.editor.view else { return }
            view.hideHoverBar()
            controller.model.showSettings = true
        }
        at(3.2) { shot("settings.png") }
        at(3.4) { panels.current?.model.showSettings = false }
        at(4.2) {
            guard let controller = panels.current, let view = controller.model.editor.view else { return }
            let range = (view.string as NSString).range(of: "breaks the flow")
            view.setSelectedRange(range)
            view.insertText("throws you out of the conversation", replacementRange: range)
            controller.model.showDiff = true
        }
        at(5.2) { shot("changes.png") }
        at(5.5) { exit(0) }
    }

    /// `styled` wraps the window the way a Mac screenshot looks: rounded corners, traffic lights,
    /// a soft shadow, an ambient background. Plain renders are for checking layout.
    static func write(_ controller: PanelController?, to path: String, styled: Bool = false) {
        guard let controller = controller, let view = controller.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let window = NSImage(size: view.bounds.size)
        window.addRepresentation(rep)
        if let (barRep, frame) = controller.model.editor.view?.hoverBarSnapshot() {
            let bar = NSImage(size: frame.size)
            bar.addRepresentation(barRep)
            window.lockFocus()
            bar.draw(in: frame)
            window.unlockFocus()
        }
        let final = styled ? framed(window, restingSize: window.size, alpha: 1, scale: 2, lift: 0) : window
        if let tiff = final.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    /// `restingSize` is the window's normal size; a smaller `window` (mid-animation) is centred in that space.
    private static func framed(_ window: NSImage, restingSize: NSSize, alpha: CGFloat, scale: CGFloat, lift: CGFloat) -> NSImage {
        let margin = NSSize(width: 120, height: 96)
        let size = NSSize(width: restingSize.width + margin.width * 2, height: restingSize.height + margin.height * 2)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return window }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let canvas = NSRect(origin: .zero, size: size)

        // Ambient background: a slow diagonal gradient with a warm glow and a teal glow behind the window.
        NSGradient(colorsAndLocations: (NSColor(hex: 0xE7F1EE), 0), (NSColor(hex: 0xF3EEE4), 0.55), (NSColor(hex: 0xE6E9F3), 1))?
            .draw(in: canvas, angle: -30)
        for (colour, centre, radius) in [(NSColor(hex: 0x14A38F).withAlphaComponent(0.18), NSPoint(x: size.width * 0.18, y: size.height * 0.85), size.width * 0.5),
                                         (NSColor(hex: 0xF2B58A).withAlphaComponent(0.22), NSPoint(x: size.width * 0.88, y: size.height * 0.1), size.width * 0.45)] {
            NSGradient(colors: [colour, colour.withAlphaComponent(0)])?.draw(fromCenter: centre, radius: 0, toCenter: centre, radius: radius, options: [])
        }

        // The window: shadow, rounded corners, then the traffic lights the render does not include.
        let frame = NSRect(x: margin.width + (restingSize.width - window.size.width) / 2,
                           y: margin.height + (restingSize.height - window.size.height) / 2 + lift,
                           width: window.size.width, height: window.size.height)
        let shape = NSBezierPath(roundedRect: frame, xRadius: 11, yRadius: 11)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 44
        shadow.shadowOffset = NSSize(width: 0, height: -22)
        shadow.set()
        NSColor.white.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        shape.addClip()
        window.draw(in: frame, from: NSRect(origin: .zero, size: window.size), operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.08 * alpha).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        for (i, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            let dot = NSRect(x: frame.minX + 13 + CGFloat(i) * 20, y: frame.maxY - 13 - 12, width: 12, height: 12)
            NSColor(hex: hex).withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }
}
