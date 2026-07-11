import AppKit

/// Always-on-top, non-activating panel that hosts the widget UI.
/// Non-activating means clicking the widget never steals focus from
/// the app the user is reading.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .utilityWindow
    }

    // Borderless panels refuse key status by default; the slider and
    // steppers need it to receive events.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
