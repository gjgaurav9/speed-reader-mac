import AppKit
import Carbon.HIToolbox
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var widgetPanel: FloatingPanel!
    private let settings = AppSettings.shared
    private let widgetModel = WidgetViewModel()

    private static let widgetFrameKey = "widgetFrame"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpWidgetPanel()
        setUpHotKeys()
        showWidget()
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "hare.fill",
            accessibilityDescription: "Speed Reader"
        )

        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: "Show/Hide Widget",
            action: #selector(toggleWidget),
            keyEquivalent: "r"
        )
        toggleItem.keyEquivalentModifierMask = [.option, .shift]
        toggleItem.target = self
        menu.addItem(toggleItem)

        let readItem = NSMenuItem(
            title: "Read Screen",
            action: #selector(startReading),
            keyEquivalent: ""
        )
        readItem.target = self
        menu.addItem(readItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Speed Reader",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    // MARK: - Widget panel

    private func setUpWidgetPanel() {
        widgetPanel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 220))

        let content = WidgetView(
            settings: settings,
            model: widgetModel,
            onStartReading: { [weak self] in self?.startReading() },
            onClose: { [weak self] in self?.hideWidget() }
        )
        let hosting = NSHostingView(rootView: content)
        widgetPanel.contentView = hosting

        if let saved = UserDefaults.standard.string(forKey: Self.widgetFrameKey) {
            widgetPanel.setFrame(NSRectFromString(saved), display: false)
        } else {
            positionWidgetTopRight()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(widgetMoved),
            name: NSWindow.didMoveNotification,
            object: widgetPanel
        )
    }

    private func positionWidgetTopRight() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = widgetPanel.frame.size
        let origin = NSPoint(
            x: visible.maxX - size.width - 24,
            y: visible.maxY - size.height - 24
        )
        widgetPanel.setFrameOrigin(origin)
    }

    @objc private func widgetMoved() {
        UserDefaults.standard.set(
            NSStringFromRect(widgetPanel.frame),
            forKey: Self.widgetFrameKey
        )
    }

    // MARK: - Hotkeys

    private func setUpHotKeys() {
        // ⌥⇧R — toggle the widget from anywhere.
        HotKeyCenter.shared.register(
            keyCode: kVK_ANSI_R,
            modifiers: optionKey | shiftKey
        ) { [weak self] in
            self?.toggleWidget()
        }
    }

    // MARK: - Actions

    @objc private func toggleWidget() {
        widgetPanel.isVisible ? hideWidget() : showWidget()
    }

    private func showWidget() {
        // Clamp back on screen in case displays changed since last run.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(widgetPanel.frame) }) {
            positionWidgetTopRight()
        }
        widgetPanel.orderFrontRegardless()
    }

    private func hideWidget() {
        widgetPanel.orderOut(nil)
    }

    @objc private func startReading() {
        // Milestone 2 wires this to capture + OCR.
        showWidget()
        widgetModel.flash("Capture + OCR arrives in Milestone 2 — controls and widget are live.")
    }
}
