import AppKit

struct ReadingStats {
    let wordsRead: Int
    let elapsed: TimeInterval
    let finished: Bool

    var effectiveWPM: Int {
        elapsed > 1 ? Int(Double(wordsRead) / elapsed * 60) : 0
    }
}

/// Runs a guided reading session over a captured region: highlights chunks
/// one by one at the configured WPM. Focus mode shows the frozen capture and
/// dims everything but the current line; Guide mode draws only the highlight
/// over the live screen.
///
/// Controls: Space/click pause · ←/→ sentence jump · ↑/↓ speed · Esc exit.
final class ReadingOverlay {
    /// Called when the user scrolls during a session with auto re-read on:
    /// the session has already ended; the owner should watch for the scroll
    /// to settle and re-capture.
    var onScrolledAway: (() -> Void)?

    private var window: OverlayWindow?
    private var view: ReaderView?
    private var script: ReadingScript?
    private var stepWork: DispatchWorkItem?
    private var speech: SpeechPacer?

    private var index = 0
    private var paused = false
    private var startedAt = Date()
    private var onFinish: ((ReadingStats) -> Void)?

    private let settings = AppSettings.shared

    private var isSpeaking: Bool { speech != nil }

    var isActive: Bool { window != nil }

    func start(
        capture: CaptureResult,
        result: OCRResult,
        onFinish: @escaping (ReadingStats) -> Void
    ) {
        stop(finished: false, notify: false)

        let script = ReadingScript.build(from: result, chunkSize: settings.chunkSize)
        guard !script.chunks.isEmpty else { return }

        self.script = script
        self.onFinish = onFinish
        index = 0
        paused = false
        startedAt = Date()

        let window = OverlayWindow(contentRect: capture.region)
        let view = ReaderView(
            capture: capture,
            script: script,
            mode: settings.readingMode,
            style: settings.guideStyle,
            accent: settings.guideColor.nsColor,
            dimOpacity: settings.dimOpacity
        )
        view.onKey = { [weak self] key in self?.handle(key) }
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        self.view = view

        render()
        if settings.readAloud {
            let pacer = SpeechPacer()
            pacer.onChunk = { [weak self] chunkIndex in
                guard let self else { return }
                self.index = chunkIndex
                self.render()
            }
            pacer.onFinished = { [weak self] in
                guard let self else { return }
                self.index = self.script?.chunks.count ?? self.index
                self.stop(finished: true)
            }
            speech = pacer
            pacer.start(script: script, from: 0, wpm: settings.wpm)
        } else {
            scheduleStep()
        }
    }

    func stop(finished: Bool = false, notify: Bool = true) {
        stepWork?.cancel()
        stepWork = nil
        speech?.stop()
        speech = nil
        window?.orderOut(nil)
        window = nil
        view = nil

        if notify, let script, let onFinish {
            let read = script.chunks[..<min(index, script.chunks.count)]
                .reduce(0) { $0 + $1.text.split(separator: " ").count }
            onFinish(ReadingStats(
                wordsRead: read,
                elapsed: Date().timeIntervalSince(startedAt),
                finished: finished
            ))
        }
        script = nil
        onFinish = nil
    }

    // MARK: - Stepping

    private func scheduleStep() {
        guard let script, !paused else { return }
        guard index < script.chunks.count else {
            stop(finished: true)
            return
        }
        let seconds = script.chunks[index].weight * 60.0 / max(settings.wpm, 50)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.index += 1
            self.render()
            self.scheduleStep()
        }
        stepWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func render() {
        guard let script, let view else { return }
        guard index < script.chunks.count else { return }
        let remaining = script.remainingWeight(from: index) * 60.0 / max(settings.wpm, 50)
        view.update(
            index: index,
            paused: paused,
            wpm: Int(settings.wpm),
            progress: script.totalWeight > 0
                ? 1 - script.remainingWeight(from: index) / script.totalWeight
                : 0,
            remaining: remaining
        )
    }

    // MARK: - Controls

    private func handle(_ key: ReaderView.Key) {
        guard let script else { return }
        switch key {
        case .togglePause:
            paused.toggle()
            if let speech {
                paused ? speech.pause() : speech.resume()
            } else if paused {
                stepWork?.cancel()
            } else {
                scheduleStep()
            }
            render()
        case .previousSentence:
            index = script.sentenceStart(before: index)
            restartStep()
        case .nextSentence:
            if let next = script.sentenceStart(after: index) {
                index = next
                restartStep()
            }
        case .faster:
            settings.wpm = min(settings.wpm + 25, AppSettings.wpmRange.upperBound)
            applySpeedChange()
        case .slower:
            settings.wpm = max(settings.wpm - 25, AppSettings.wpmRange.lowerBound)
            applySpeedChange()
        case .exit:
            stop(finished: false)
        case .scrolled:
            // The frozen frame is stale once the user scrolls the content
            // underneath. End the session and hand off to auto re-read.
            if settings.autoReread {
                stop(finished: false)
                onScrolledAway?()
            }
        }
    }

    /// An utterance's rate is fixed once started, so speed changes while
    /// speaking restart the voice from the current chunk at the new rate.
    private func applySpeedChange() {
        if isSpeaking {
            restartStep()
        } else {
            render()
        }
    }

    private func restartStep() {
        stepWork?.cancel()
        paused = false
        render()
        if let speech, let script {
            speech.start(script: script, from: index, wpm: settings.wpm)
        } else {
            scheduleStep()
        }
    }
}

// MARK: - View

private final class ReaderView: NSView {
    enum Key {
        case togglePause, previousSentence, nextSentence, faster, slower, exit, scrolled
    }

    var onKey: ((Key) -> Void)?

    private let capture: CaptureResult
    private let script: ReadingScript
    private let mode: ReadingMode
    private let style: GuideStyle
    private let accent: NSColor
    private let dimOpacity: Double

    private var index = 0
    private var paused = false
    private var wpm = 300
    private var progress: Double = 0
    private var remaining: TimeInterval = 0

    init(
        capture: CaptureResult,
        script: ReadingScript,
        mode: ReadingMode,
        style: GuideStyle,
        accent: NSColor,
        dimOpacity: Double
    ) {
        self.capture = capture
        self.script = script
        self.mode = mode
        self.style = style
        self.accent = accent
        self.dimOpacity = dimOpacity
        super.init(frame: NSRect(origin: .zero, size: capture.region.size))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(index: Int, paused: Bool, wpm: Int, progress: Double, remaining: TimeInterval) {
        self.index = index
        self.paused = paused
        self.wpm = wpm
        self.progress = progress
        self.remaining = remaining
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onKey?(.togglePause)
    }

    override func scrollWheel(with event: NSEvent) {
        onKey?(.scrolled)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onKey?(.exit)              // Esc
        case 49: onKey?(.togglePause)       // Space
        case 123: onKey?(.previousSentence) // ←
        case 124: onKey?(.nextSentence)     // →
        case 126: onKey?(.faster)           // ↑
        case 125: onKey?(.slower)           // ↓
        default: super.keyDown(with: event)
        }
    }

    private func local(_ rect: NSRect) -> NSRect {
        rect.offsetBy(dx: -capture.region.minX, dy: -capture.region.minY)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard index < script.chunks.count else { return }
        let chunk = script.chunks[index]
        let chunkRect = local(chunk.rect)
        let lineRect = lineRect(for: chunk.lineIndex)

        if mode == .focus {
            // Frozen frame + dim everything except the current line.
            let image = NSImage(cgImage: capture.image, size: capture.region.size)
            image.draw(in: bounds)

            let dim = NSBezierPath(rect: bounds)
            dim.append(NSBezierPath(roundedRect: lineRect.insetBy(dx: -6, dy: -4), xRadius: 4, yRadius: 4))
            dim.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(dimOpacity).setFill()
            dim.fill()
        }

        drawGuide(chunkRect: chunkRect, lineRect: lineRect)
        drawHUD()
    }

    /// Union of word rects on the chunk's line, so the ruler/dim window
    /// covers the whole visual line.
    private func lineRect(for lineIndex: Int) -> NSRect {
        let lineChunks = script.chunks.filter { $0.lineIndex == lineIndex }
        guard let first = lineChunks.first else { return .zero }
        return local(lineChunks.dropFirst().reduce(first.rect) { $0.union($1.rect) })
    }

    private func drawGuide(chunkRect: NSRect, lineRect: NSRect) {
        switch style {
        case .wordHighlight:
            let box = NSBezierPath(
                roundedRect: chunkRect.insetBy(dx: -3, dy: -2),
                xRadius: 4,
                yRadius: 4
            )
            accent.withAlphaComponent(0.28).setFill()
            box.fill()
            accent.setStroke()
            box.lineWidth = 1.5
            box.stroke()

        case .underline:
            let bar = NSRect(
                x: chunkRect.minX - 2,
                y: chunkRect.minY - 4,
                width: chunkRect.width + 4,
                height: 3
            )
            accent.setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()

        case .ruler:
            // Soft band across the current line; the chunk gets a subtle tick.
            let band = lineRect.insetBy(dx: -6, dy: -4)
            accent.withAlphaComponent(mode == .focus ? 0.12 : 0.18).setFill()
            NSBezierPath(roundedRect: band, xRadius: 4, yRadius: 4).fill()
            let tick = NSRect(
                x: chunkRect.minX - 2,
                y: chunkRect.minY - 4,
                width: chunkRect.width + 4,
                height: 2.5
            )
            accent.setFill()
            NSBezierPath(roundedRect: tick, xRadius: 1, yRadius: 1).fill()
        }
    }

    private func drawHUD() {
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        let state = paused ? "paused" : String(format: "%d:%02d left", minutes, seconds)
        let text = "\(wpm) wpm · \(Int(progress * 100))% · \(state)   ·   space pause · ←→ sentence · ↑↓ speed · esc exit"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95),
        ]
        let size = text.size(withAttributes: attributes)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: 10)
        let badge = NSRect(origin: origin, size: size).insetBy(dx: -10, dy: -6)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 8, yRadius: 8).fill()
        text.draw(at: origin, withAttributes: attributes)

        // Thin progress bar along the badge's top edge.
        let track = NSRect(x: badge.minX, y: badge.maxY - 2, width: badge.width, height: 2)
        NSColor.white.withAlphaComponent(0.2).setFill()
        track.fill()
        accent.setFill()
        NSRect(x: track.minX, y: track.minY, width: track.width * progress, height: 2).fill()
    }
}
