import AppKit
import Combine
import SwiftUI

/// One window for one piece of copy. Completes exactly once, with the result or a cancellation.
final class PanelController: NSObject, NSWindowDelegate {
    let model: EditorModel
    private let panel: NSPanel
    private var completion: ((WriteResult) -> Void)?
    private var subscriptions: [AnyCancellable] = []

    init(request: WriteRequest, completion: @escaping (WriteResult) -> Void) {
        self.model = EditorModel(request: request)
        self.completion = completion
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.title = request.title
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = Theme.NS.canvas
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 820, height: 520)
        panel.delegate = self

        let view = PanelView(
            model: model,
            onSend: { [weak self] in self?.send() },
            onCancel: { [weak self] in self?.requestCancel() },
            onConfirm: { [weak self] in self?.confirm() },
            onDismiss: { [weak self] in self?.dismissConfirmation() }
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.contentView?.wantsLayer = true      // up front, so the first animation never flips backing mid-flight
        panel.center()
        panel.setFrameAutosaveName("your-turn.panel")

        let settings = Settings.shared
        panel.appearance = settings.appearance
        settings.$theme.dropFirst().sink { [weak self] _ in
            guard let self = self else { return }
            self.crossfade {
                self.panel.appearance = settings.appearance
                self.panel.backgroundColor = Theme.NS.canvas
                self.model.editor.view?.applyTheme()
            }
        }.store(in: &subscriptions)
        settings.$textSize.dropFirst().sink { [weak self] _ in self?.model.editor.view?.applyTextSize() }.store(in: &subscriptions)
    }

    var contentView: NSView? { panel.contentView }
    var window: NSWindow { panel }

    /// Freezes the current look as an image over the content, applies `change`, then fades the image out.
    private func crossfade(_ change: () -> Void) {
        guard let content = panel.contentView, let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { change(); return }
        content.cacheDisplay(in: content.bounds, to: rep)
        let image = NSImage(size: content.bounds.size)
        image.addRepresentation(rep)
        let veil = NSImageView(frame: content.bounds)
        veil.image = image
        veil.imageScaling = .scaleAxesIndependently
        veil.autoresizingMask = [.width, .height]
        content.addSubview(veil)
        change()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.45
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                veil.animator().alphaValue = 0
            }, completionHandler: { veil.removeFromSuperview() })
        }
    }

    /// The content layer, anchored at its centre so scale animations do not shift it.
    private var contentLayer: CALayer? {
        guard let view = panel.contentView else { return nil }
        view.wantsLayer = true
        guard let layer = view.layer else { return nil }
        if layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        }
        return layer
    }

    /// Scales and lifts the content without touching the window frame, so nothing reflows.
    /// The layer is rasterised for the duration, so it moves as one bitmap instead of re-drawing text every frame.
    private func animateContent(from: (scale: CGFloat, lift: CGFloat), to: (scale: CGFloat, lift: CGFloat), duration: Double, curve: CAMediaTimingFunction) {
        guard let layer = contentLayer else { return }
        func transform(_ t: (scale: CGFloat, lift: CGFloat)) -> CATransform3D {
            CATransform3DConcat(CATransform3DMakeScale(t.scale, t.scale, 1), CATransform3DMakeTranslation(0, t.lift, 0))
        }
        layer.rasterizationScale = panel.backingScaleFactor
        layer.shouldRasterize = true
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak layer] in layer?.shouldRasterize = false }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = transform(from)
        animation.toValue = transform(to)
        animation.duration = duration
        animation.timingFunction = curve
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "motion")
        CATransaction.commit()
    }

    /// For renders: on a far corner of the screen, never key, never activating the app.
    func showQuietly() {
        guard let screen = NSScreen.main else { return }
        var frame = panel.frame
        frame.origin = NSPoint(x: screen.frame.maxX - 40, y: screen.frame.minY - frame.height + 40)
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        if let view = model.editor.view { panel.makeFirstResponder(view) }
    }

    /// Keeps the saved size, opens in the middle of the screen, and eases in rather than blinking on.
    func show() {
        var frame = panel.frame
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
        }
        panel.setFrame(frame, display: false)
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        animateContent(from: (0.96, -14), to: (1, 0), duration: 0.42, curve: CAMediaTimingFunction(controlPoints: 0.16, 0.84, 0.3, 1))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.34
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        // Ready to type: the editor takes focus with the caret at the start, once SwiftUI has built it.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let view = self.model.editor.view else { return }
            self.panel.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: 0, length: 0))
        }
    }

    private func finish(_ result: WriteResult) {
        guard let done = completion else { return }
        completion = nil
        panel.delegate = nil
        panel.orderOut(nil)
        if result.status == .sent || model.isDirty { History.record(title: model.request.title, result: result) }
        done(result)
    }

    /// Confirmation sheets take the keyboard so Return and Esc mean the sheet, not the text.
    private func ask(_ confirmation: EditorModel.Confirmation) {
        model.editor.view?.hideHoverBar()
        panel.makeFirstResponder(nil)
        model.confirmation = confirmation
    }

    private func dismissConfirmation() {
        model.confirmation = nil
        if let view = model.editor.view { panel.makeFirstResponder(view) }
    }

    private func confirm() {
        guard let confirmation = model.confirmation else { return }
        model.confirmation = nil
        switch confirmation {
        case .discard: finish(.cancelled)
        case .sendEmpty: send(force: true)
        }
    }

    /// The window lifts and fades on its way out, then the result is delivered.
    private func send(force: Bool = false) {
        guard completion != nil, model.confirmation == nil else { return }
        if !force, model.hasDraft, model.text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ask(.sendEmpty)
            return
        }
        let result = model.result()
        panel.makeFirstResponder(nil)
        model.editor.view?.hideHoverBar()
        animateContent(from: (1, 0), to: (0.9, 120), duration: 0.55, curve: CAMediaTimingFunction(controlPoints: 0.5, 0, 0.8, 0.5))
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.8, 0.5)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.finish(result)
            self.contentLayer?.removeAllAnimations()
            self.panel.alphaValue = 1
        })
    }

    /// Confirms before throwing away edits.
    func requestCancel() {
        guard completion != nil, model.confirmation == nil else { return }
        guard model.isDirty else { finish(.cancelled); return }
        ask(.discard)
    }

    // MARK: Actions reached through the responder chain (text view → hosting view → panel → delegate)

    @objc func sendCopy(_ sender: Any?) { send() }

    @objc func cancelCopy(_ sender: Any?) {
        if model.confirmation != nil { dismissConfirmation(); return }
        if model.showSettings { model.showSettings = false; return }
        if model.showDiff { model.showDiff = false; return }
        requestCancel()
    }

    @objc func togglePoint(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        model.togglePoint(item.tag - 1)
    }

    @objc func addPoint(_ sender: Any?) { model.addPoint() }
    @objc func toggleSettings(_ sender: Any?) { model.showSettings.toggle() }
    @objc func toggleDiff(_ sender: Any?) { if model.hasDraft { model.showDiff.toggle() } }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        requestCancel()
        return false
    }
}
