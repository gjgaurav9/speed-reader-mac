import AppKit

/// Full-screen drag-to-select, like the system screenshot tool.
/// Creates one selection window per display; Esc cancels.
final class RegionSelector {
    struct Selection {
        let rect: NSRect      // AppKit global coords
        let screen: NSScreen
    }

    private var windows: [SelectionWindow] = []
    private var completion: ((Selection?) -> Void)?

    func begin(completion: @escaping (Selection?) -> Void) {
        guard windows.isEmpty else { return }
        self.completion = completion

        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen)
            window.selectionView.onFinished = { [weak self] rect in
                self?.finish(rect.map { Selection(rect: $0, screen: screen) })
            }
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.set()
    }

    private func finish(_ selection: Selection?) {
        guard completion != nil else { return }
        for window in windows {
            window.orderOut(nil)
        }
        windows = []
        NSCursor.arrow.set()
        let completion = self.completion
        self.completion = nil
        completion?(selection)
    }
}

private final class SelectionWindow: NSWindow {
    let selectionView: SelectionView

    init(screen: NSScreen) {
        selectionView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var onFinished: ((NSRect?) -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    private var selectionRect: NSRect? {
        guard let startPoint, let currentPoint else { return nil }
        return NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            startPoint = nil
            currentPoint = nil
        }
        guard let rect = selectionRect, rect.width > 24, rect.height > 12,
              let window
        else {
            onFinished?(nil)
            return
        }
        // View coords → global screen coords.
        let windowRect = convert(rect, to: nil)
        onFinished?(window.convertToScreen(windowRect))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onFinished?(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        guard let rect = selectionRect else { return }

        // Punch out the selected area so the user sees it clearly.
        rect.fill(using: .clear)

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 2
        border.stroke()

        // Size badge under the selection.
        let label = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attributes)
        let badgeOrigin = NSPoint(x: rect.minX + 4, y: max(rect.minY - size.height - 8, 4))
        let badgeRect = NSRect(origin: badgeOrigin, size: size).insetBy(dx: -6, dy: -3)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4).fill()
        label.draw(at: badgeOrigin, withAttributes: attributes)
    }
}
