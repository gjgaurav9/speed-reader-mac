import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
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
    private let stats = StatsStore.shared
    private var hasRequestedScreenPermission = false
    private var lastSelection: RegionSelector.Selection?

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
            keyEquivalent: "s"
        )
        readItem.keyEquivalentModifierMask = [.option, .shift]
        readItem.target = self
        menu.addItem(readItem)

        let againItem = NSMenuItem(
            title: "Read Same Region Again",
            action: #selector(readSameRegion),
            keyEquivalent: "a"
        )
        againItem.keyEquivalentModifierMask = [.option, .shift]
        againItem.target = self
        menu.addItem(againItem)

        let debugItem = NSMenuItem(
            title: "Show OCR Boxes (Debug)",
            action: #selector(startDebugBoxes),
            keyEquivalent: ""
        )
        debugItem.target = self
        menu.addItem(debugItem)

        let displayItem = NSMenuItem(
            title: "Change Shared Display…",
            action: #selector(changeSharedDisplay),
            keyEquivalent: ""
        )
        displayItem.target = self
        menu.addItem(displayItem)

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
            stats: stats,
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
        // ⌥⇧S — start reading (region select) from anywhere.
        HotKeyCenter.shared.register(
            keyCode: kVK_ANSI_S,
            modifiers: optionKey | shiftKey
        ) { [weak self] in
            self?.startReading()
        }
        // ⌥⇧A — re-read the last region (e.g. after scrolling to new text).
        HotKeyCenter.shared.register(
            keyCode: kVK_ANSI_A,
            modifiers: optionKey | shiftKey
        ) { [weak self] in
            self?.readSameRegion()
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

    /// Re-capture and read the previously selected region — the quick way to
    /// continue after scrolling to the next page of text.
    @objc private func readSameRegion() {
        guard let lastSelection else {
            widgetModel.flash("No region yet — use Read Screen (⌥⇧S) first.")
            return
        }
        dismissOverlays()
        Task { @MainActor in
            guard let route = await obtainCaptureRoute() else { return }
            await read(selection: lastSelection, debugBoxes: false, route: route)
        }
    }

    /// Forget the picked display; the next capture re-presents the picker.
    @objc private func changeSharedDisplay() {
        Task { @MainActor in
            ContentPickerSession.shared.invalidate()
        }
        widgetModel.flash("Pick a display on the next Read Screen.")
    }

    private func beginCapture(debugBoxes: Bool) {
        dismissOverlays()
        Task { @MainActor in
            guard let route = await obtainCaptureRoute() else { return }
            self.showWidget()
            self.regionSelector.begin { [weak self] selection in
                guard let self, let selection else { return }
                self.lastSelection = selection
                Task { @MainActor in
                    await self.read(selection: selection, debugBoxes: debugBoxes, route: route)
                }
            }
        }
    }

    private enum CaptureRoute {
        /// System-picker filter: silent captures, no recurring consent prompt.
        case picker(SCContentFilter)
        /// Direct ScreenCaptureKit capture: needs the Screen Recording TCC
        /// grant and triggers the recurring macOS consent prompt.
        case legacy
    }

    @MainActor
    private func obtainCaptureRoute() async -> CaptureRoute? {
        switch await ContentPickerSession.shared.obtainFilter() {
        case .filter(let filter):
            return .picker(filter)
        case .cancelled:
            widgetModel.flash("Display sharing cancelled.")
            return nil
        case .failed:
            widgetModel.flash("System picker unavailable — using direct capture.", for: 4)
            return ensureScreenPermission() ? .legacy : nil
        }
    }

    private func dismissOverlays() {
        if debugOverlay.isVisible {
            debugOverlay.dismiss()
        }
        if readingOverlay.isActive {
            readingOverlay.stop(notify: false)
        }
    }

    private func ensureScreenPermission() -> Bool {
        guard !ScreenCapture.hasPermission() else { return true }
        if !hasRequestedScreenPermission {
            // First ask: let the system prompt show on its own — opening
            // System Settings at the same time can hide it.
            hasRequestedScreenPermission = true
            ScreenCapture.requestPermission()
            widgetModel.flash(
                "macOS is asking for Screen Recording — allow it, then quit and reopen Speed Reader.",
                for: 12
            )
        } else {
            widgetModel.flash(
                "Still no permission. Add SpeedReader.app with the + button in System Settings, then quit and reopen.",
                for: 12
            )
            ScreenCapture.openSystemSettings()
        }
        return false
    }

    @MainActor
    private func read(selection: RegionSelector.Selection, debugBoxes: Bool, route: CaptureRoute) async {
        do {
            widgetModel.flash("Reading…", for: 30)

            // Hide our own windows during the capture: the picker filter
            // captures the whole display, including the widget.
            let widgetWasVisible = widgetPanel.isVisible
            if widgetWasVisible { widgetPanel.orderOut(nil) }
            try? await Task.sleep(nanoseconds: 80_000_000)

            let capture: CaptureResult
            do {
                switch route {
                case .picker(let filter):
                    capture = try await ScreenCapture.capture(region: selection.rect, using: filter)
                case .legacy:
                    capture = try await ScreenCapture.capture(region: selection.rect, on: selection.screen)
                }
            } catch {
                if widgetWasVisible { showWidget() }
                throw error
            }
            if widgetWasVisible { showWidget() }
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
                readingOverlay.start(capture: capture, result: result) { [weak self] sessionStats in
                    self?.stats.record(sessionStats)
                    let verb = sessionStats.finished ? "Finished" : "Stopped"
                    self?.widgetModel.flash(
                        "\(verb): \(sessionStats.wordsRead) words in \(Int(sessionStats.elapsed))s · \(sessionStats.effectiveWPM) wpm effective",
                        for: 8
                    )
                }
            }
        } catch {
            widgetModel.flash("Capture failed: \(error.localizedDescription)", for: 8)
        }
    }
}
