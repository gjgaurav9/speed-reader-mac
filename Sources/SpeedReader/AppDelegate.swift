import AppKit
import Carbon.HIToolbox
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var widgetPanel: FloatingPanel!
    private var hostingView: NSHostingView<WidgetView>!
    private let settings = AppSettings.shared
    private let widgetModel = WidgetViewModel()

    private let regionSelector = RegionSelector()
    private let debugOverlay = DebugOverlay()
    private let readingOverlay = ReadingOverlay()

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

        let debugItem = NSMenuItem(
            title: "Show OCR Boxes (Debug)",
            action: #selector(startDebugBoxes),
            keyEquivalent: ""
        )
        debugItem.target = self
        menu.addItem(debugItem)

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
            onToggleCollapse: { [weak self] in self?.toggleCollapsed() }
        )
        hostingView = NSHostingView(rootView: content)
        widgetPanel.contentView = hostingView

        if let saved = UserDefaults.standard.string(forKey: Self.widgetFrameKey) {
            widgetPanel.setFrame(NSRectFromString(saved), display: false)
        } else {
            positionWidgetTopRight()
        }
        // Normalize the frame to the current content (the saved frame may
        // have been stored while collapsed).
        DispatchQueue.main.async { [weak self] in
            self?.resizePanelKeepingTopRight(animate: false)
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

    /// Resize the panel to fit the SwiftUI content, keeping the top-right
    /// corner where the user put it (widget lives in a corner, so the
    /// top-right anchor feels stationary when collapsing/expanding).
    private func resizePanelKeepingTopRight(animate: Bool) {
        let size = hostingView.fittingSize
        guard size.width > 1, size.height > 1 else { return }
        let old = widgetPanel.frame
        let newFrame = NSRect(
            x: old.maxX - size.width,
            y: old.maxY - size.height,
            width: size.width,
            height: size.height
        )
        widgetPanel.setFrame(newFrame, display: true, animate: animate)
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

    // MARK: - Widget visibility

    @objc private func toggleWidget() {
        widgetPanel.isVisible ? widgetPanel.orderOut(nil) : showWidget()
    }

    private func showWidget() {
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(widgetPanel.frame) }) {
            positionWidgetTopRight()
        }
        widgetPanel.orderFrontRegardless()
    }

    private func toggleCollapsed() {
        widgetModel.isCollapsed.toggle()
        DispatchQueue.main.async { [weak self] in
            self?.resizePanelKeepingTopRight(animate: true)
        }
    }

    // MARK: - Reading pipeline (select region → capture → OCR → read)

    @objc private func startReading() {
        beginCapture(debugBoxes: false)
    }

    @objc private func startDebugBoxes() {
        beginCapture(debugBoxes: true)
    }

    private func beginCapture(debugBoxes: Bool) {
        if debugOverlay.isVisible {
            debugOverlay.dismiss()
        }
        if readingOverlay.isActive {
            readingOverlay.stop(notify: false)
        }

        guard ScreenCapture.hasPermission() else {
            ScreenCapture.requestPermission()
            widgetModel.flash(
                "Enable Screen Recording for Speed Reader in System Settings, then quit and reopen.",
                for: 10
            )
            ScreenCapture.openSystemSettings()
            return
        }

        showWidget()
        regionSelector.begin { [weak self] selection in
            guard let self, let selection else { return }
            Task { @MainActor in
                await self.read(selection: selection, debugBoxes: debugBoxes)
            }
        }
    }

    @MainActor
    private func read(selection: RegionSelector.Selection, debugBoxes: Bool) async {
        do {
            widgetModel.flash("Reading…", for: 30)
            let capture = try await ScreenCapture.capture(
                region: selection.rect,
                on: selection.screen
            )
            let result = try await OCRService.recognize(capture)

            guard !result.lines.isEmpty else {
                widgetModel.flash("No text found in that region.")
                return
            }

            if debugBoxes {
                debugOverlay.show(capture: capture, result: result)
                widgetModel.flash(
                    "\(result.lines.count) lines · \(result.wordCount) words · \(Int(result.duration * 1000)) ms"
                )
            } else {
                widgetModel.flash("\(result.wordCount) words · go!", for: 3)
                readingOverlay.start(capture: capture, result: result) { [weak self] stats in
                    let verb = stats.finished ? "Finished" : "Stopped"
                    self?.widgetModel.flash(
                        "\(verb): \(stats.wordsRead) words in \(Int(stats.elapsed))s · \(stats.effectiveWPM) wpm effective",
                        for: 8
                    )
                }
            }
        } catch {
            widgetModel.flash("Capture failed: \(error.localizedDescription)", for: 8)
        }
    }
}
