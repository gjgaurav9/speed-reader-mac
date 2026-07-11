import AppKit

/// One step of the guided reading session: the words highlighted together.
struct ReadingChunk {
    let text: String
    let rect: NSRect            // union of word rects, global screen coords
    let lineIndex: Int
    /// Display duration in "word units": seconds = weight * 60 / WPM.
    let weight: Double
    let startsSentence: Bool
}

/// Flattens OCR lines into timed chunks.
///
/// Timing model (adapted from pasky/speedread + Spritz research):
///   weight = base + 0.04 * sqrt(characters)
///   base: 0.9 plain word · 1.2 multi-word chunk · 2.0 clause end (,;:)
///         3.0 sentence end (.?!)
///   + 1.0 at line ends without punctuation
///   + 2.5 before a paragraph gap
///   × 1.5 for numbers/URLs (worst-case items in RSVP studies)
struct ReadingScript {
    let chunks: [ReadingChunk]

    var totalWeight: Double { chunks.reduce(0) { $0 + $1.weight } }
    var wordCount: Int {
        chunks.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }

    func remainingWeight(from index: Int) -> Double {
        chunks[min(index, chunks.count)...].reduce(0) { $0 + $1.weight }
    }

    /// Index of the chunk starting the previous/next sentence, for ←/→.
    func sentenceStart(before index: Int) -> Int {
        var i = min(index, chunks.count - 1)
        // Step past the current sentence start so ← from a sentence's first
        // chunk goes to the previous sentence, not to itself.
        if i > 0 { i -= 1 }
        while i > 0 && !chunks[i].startsSentence { i -= 1 }
        return i
    }

    func sentenceStart(after index: Int) -> Int? {
        var i = index + 1
        while i < chunks.count {
            if chunks[i].startsSentence { return i }
            i += 1
        }
        return nil
    }

    static func build(from result: OCRResult, chunkSize: Int) -> ReadingScript {
        let lines = result.lines

        // Median vertical gap between consecutive lines, for paragraph detection.
        var gaps: [CGFloat] = []
        for (a, b) in zip(lines, lines.dropFirst()) {
            let gap = a.rect.minY - b.rect.maxY
            if gap > 0 { gaps.append(gap) }
        }
        let medianGap = gaps.isEmpty ? 0 : gaps.sorted()[gaps.count / 2]

        var chunks: [ReadingChunk] = []
        var nextStartsSentence = true

        for (lineIndex, line) in lines.enumerated() {
            let words = line.words
            guard !words.isEmpty else { continue }

            let isParagraphEnd: Bool = {
                guard lineIndex + 1 < lines.count, medianGap > 0 else { return lineIndex + 1 == lines.count }
                let gap = line.rect.minY - lines[lineIndex + 1].rect.maxY
                return gap > medianGap * 1.8
            }()

            var i = 0
            while i < words.count {
                let group = Array(words[i ..< min(i + chunkSize, words.count)])
                i += group.count
                let isLineEnd = i >= words.count

                let text = group.map(\.text).joined(separator: " ")
                let rect = group.dropFirst().reduce(group[0].rect) { $0.union($1.rect) }

                var weight = baseWeight(for: text, isMultiWord: group.count > 1)
                weight += 0.04 * (Double(text.count)).squareRoot()
                if containsNumbersOrLinks(text) {
                    weight *= 1.5
                }
                if isLineEnd {
                    if endsWithPunctuation(text) == .none { weight += 1.0 }
                    if isParagraphEnd { weight += 2.5 }
                }

                let startsSentence = nextStartsSentence
                nextStartsSentence = endsWithPunctuation(text) == .sentence

                chunks.append(ReadingChunk(
                    text: text,
                    rect: rect,
                    lineIndex: lineIndex,
                    weight: weight,
                    startsSentence: startsSentence
                ))
            }
        }

        return ReadingScript(chunks: chunks)
    }

    private enum Punctuation { case none, clause, sentence }

    private static func endsWithPunctuation(_ text: String) -> Punctuation {
        // Ignore trailing quotes/brackets: `word."` still ends the sentence.
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"')]}»›"))
        guard let last = trimmed.last else { return .none }
        if ".?!…".contains(last) { return .sentence }
        if ",;:—".contains(last) { return .clause }
        return .none
    }

    private static func baseWeight(for text: String, isMultiWord: Bool) -> Double {
        switch endsWithPunctuation(text) {
        case .sentence: return 3.0
        case .clause: return 2.0
        case .none: return isMultiWord ? 1.2 : 0.9
        }
    }

    private static func containsNumbersOrLinks(_ text: String) -> Bool {
        text.rangeOfCharacter(from: .decimalDigits) != nil
            || text.contains("/")
            || text.contains("@")
    }
}
