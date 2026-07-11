import AppKit

/// Borderless transparent window pinned above everything, used for the
/// debug box view and the reading overlay. Can become key so it receives
/// keyboard control (Esc, Space, arrows).
final class OverlayWindow: NSWindow {
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
