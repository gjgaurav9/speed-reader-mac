import AppKit

/// Milestone 2 verification overlay: draws the frozen capture back over the
/// screen, pixel-aligned, with every OCR line/word box on top. If the boxes
/// sit exactly on the words, the whole coordinate pipeline is correct.
/// Esc or click dismisses. This window is also the seed of Focus mode.
final class DebugOverlay {
    private var window: NSWindow?

    var isVisible: Bool { window != nil }

    func show(capture: CaptureResult, result: OCRResult) {
        dismiss()

        let window = OverlayWindow(contentRect: capture.region)
        window.contentView = DebugBoxesView(
            capture: capture,
            result: result,
            onDismiss: { [weak self] in self?.dismiss() }
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}

private final class OverlayWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
    }

    override var canBecomeKey: Bool { true }
}

private final class DebugBoxesView: NSView {
    private let capture: CaptureResult
    private let result: OCRResult
    private let onDismiss: () -> Void

    init(capture: CaptureResult, result: OCRResult, onDismiss: @escaping () -> Void) {
        self.capture = capture
        self.result = result
        self.onDismiss = onDismiss
        super.init(frame: NSRect(origin: .zero, size: capture.region.size))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onDismiss()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onDismiss()
        } else {
            super.keyDown(with: event)
        }
    }

    /// Global screen rect → view-local rect. The view is non-flipped, so
    /// both coordinate spaces have a bottom-left origin: just subtract the
    /// region origin.
    private func local(_ rect: NSRect) -> NSRect {
        rect.offsetBy(dx: -capture.region.minX, dy: -capture.region.minY)
    }

    override func draw(_ dirtyRect: NSRect) {
        // The frozen frame, drawn exactly where it was captured from.
        let image = NSImage(cgImage: capture.image, size: capture.region.size)
        image.draw(in: bounds)

        for line in result.lines {
            NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
            let linePath = NSBezierPath(rect: local(line.rect))
            linePath.lineWidth = 1.5
            linePath.stroke()

            NSColor.systemOrange.withAlphaComponent(0.9).setStroke()
            for word in line.words {
                let wordPath = NSBezierPath(rect: local(word.rect).insetBy(dx: -1, dy: -1))
                wordPath.lineWidth = 1
                wordPath.stroke()
            }
        }

        drawInfoBadge()
    }

    private func drawInfoBadge() {
        let text = "\(result.lines.count) lines · \(result.wordCount) words · "
            + "OCR \(Int(result.duration * 1000)) ms · Esc to dismiss"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: 12)
        let badge = NSRect(origin: origin, size: size).insetBy(dx: -10, dy: -6)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 8, yRadius: 8).fill()
        text.draw(at: origin, withAttributes: attributes)
    }
}
