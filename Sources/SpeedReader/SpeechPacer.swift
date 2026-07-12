import AVFoundation
import Foundation

/// Reads the script aloud with the on-device speech synthesizer and reports
/// which chunk is being spoken, so the visual highlight follows the voice
/// (karaoke-style). All callbacks are delivered on the main queue.
final class SpeechPacer: NSObject {
    var onChunk: ((Int) -> Void)?
    var onFinished: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    /// Character range of each chunk inside the current utterance's text,
    /// paired with the chunk's index in the script.
    private var chunkRanges: [(range: NSRange, index: Int)] = []
    private var stopping = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak the script starting at `index`. Restartable at any chunk (used
    /// for sentence jumps and speed changes, since an utterance's rate is
    /// fixed once started).
    func start(script: ReadingScript, from index: Int, wpm: Double) {
        stop()
        stopping = false

        var text = ""
        chunkRanges = []
        for (i, chunk) in script.chunks.enumerated() where i >= index {
            if !text.isEmpty { text += " " }
            let location = (text as NSString).length
            text += chunk.text
            chunkRanges.append((
                range: NSRange(location: location, length: (chunk.text as NSString).length),
                index: i
            ))
        }
        guard !text.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = Self.rate(forWPM: wpm)
        synthesizer.speak(utterance)
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    func stop() {
        stopping = true
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// AVSpeechUtteranceDefaultSpeechRate (0.5) is roughly 175–190 wpm for
    /// English voices; scale linearly and clamp to the intelligible band.
    static func rate(forWPM wpm: Double) -> Float {
        let rate = Float(0.5 * wpm / 180.0)
        return min(max(rate, 0.2), 0.72)
    }
}

extension SpeechPacer: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let chunk = chunkRanges.last {
            $0.range.location <= characterRange.location
        }
        guard let chunk else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopping else { return }
            self.onChunk?(chunk.index)
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopping else { return }
            self.onFinished?()
        }
    }
}
