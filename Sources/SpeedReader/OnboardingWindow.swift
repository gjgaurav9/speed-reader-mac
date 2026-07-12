import AppKit
import SwiftUI

/// First-run welcome window explaining the three-step flow and the hotkeys.
/// Reopenable any time via the menu bar ("Welcome Guide").
final class OnboardingController: NSObject, NSWindowDelegate {
    var onStartReading: (() -> Void)?

    private var window: NSWindow?
    private static let key = "hasOnboarded"

    func showIfNeeded() {
        if !UserDefaults.standard.bool(forKey: Self.key) {
            show()
        }
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingView(
            onStart: { [weak self] in
                self?.close()
                self?.onStartReading?()
            }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Speed Reader"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        markDone()
        window = nil
    }

    private func close() {
        markDone()
        window?.orderOut(nil)
        window = nil
    }

    private func markDone() {
        UserDefaults.standard.set(true, forKey: Self.key)
    }
}

private struct OnboardingView: View {
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "hare.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                Text("Speed Reader")
                    .font(.title.weight(.semibold))
                Text("A reading pacer for anything on your screen")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                step(
                    icon: "macwindow.on.rectangle",
                    title: "Pick your display — once per launch",
                    detail: "The first read shows Apple's screen picker. Choose your display; every capture after that is silent and stays on your Mac."
                )
                step(
                    icon: "rectangle.dashed",
                    title: "Drag over any text",
                    detail: "Press ⌥⇧S anywhere, drag a box around what you want to read — an article, PDF, chat, code, anything visible."
                )
                step(
                    icon: "text.line.first.and.arrowtriangle.forward",
                    title: "Follow the highlight",
                    detail: "The highlight paces you word by word. Space pauses, ←/→ jump sentences, ↑/↓ change speed, Esc exits. Scroll and it re-reads automatically."
                )
            }
            .frame(maxWidth: 420)

            HStack(spacing: 12) {
                Text("⌥⇧S read · ⌥⇧A read again · ⌥⇧R widget")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: onStart) {
                Label("Start Reading", systemImage: "text.viewfinder")
                    .frame(maxWidth: 220)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 500)
    }

    private func step(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
