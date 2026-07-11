import AppKit
import Vision

/// A recognized word with its rect in AppKit global screen coordinates.
struct OCRWord {
    let text: String
    let rect: NSRect
}

/// A recognized line of text, top-to-bottom sorted within `OCRResult`.
struct OCRLine {
    let text: String
    let rect: NSRect
    let words: [OCRWord]
    let confidence: Float
}

struct OCRResult {
    let lines: [OCRLine]
    let duration: TimeInterval

    var wordCount: Int { lines.reduce(0) { $0 + $1.words.count } }
}

enum OCRService {
    /// Runs Vision text recognition on a capture and returns lines/words
    /// with rects already converted to AppKit global screen coordinates.
    static func recognize(_ capture: CaptureResult) async throws -> OCRResult {
        let started = Date()
        let lines: [OCRLine] = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { Self.line(from: $0, capture: capture) }
                    // Reading order: top of screen first (AppKit y grows upward).
                    .sorted { $0.rect.maxY > $1.rect.maxY }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: capture.image)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        return OCRResult(lines: lines, duration: Date().timeIntervalSince(started))
    }

    private static func line(from observation: VNRecognizedTextObservation, capture: CaptureResult) -> OCRLine? {
        guard let candidate = observation.topCandidates(1).first else { return nil }
        let text = candidate.string

        var words: [OCRWord] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { substring, range, _, _ in
            guard let substring,
                  let box = try? candidate.boundingBox(for: range)
            else { return }
            words.append(OCRWord(text: substring, rect: screenRect(normalized: box.boundingBox, capture: capture)))
        }

        return OCRLine(
            text: text,
            rect: screenRect(normalized: observation.boundingBox, capture: capture),
            words: words,
            confidence: candidate.confidence
        )
    }

    /// Vision boxes are normalized 0-1 with bottom-left origin, relative to
    /// the captured image. The captured image's bottom-left corner is the
    /// region's bottom-left corner in AppKit coords (both grow upward), so
    /// the mapping is: normalized → image pixels → ÷scale → +region origin.
    private static func screenRect(normalized: CGRect, capture: CaptureResult) -> NSRect {
        let px = VNImageRectForNormalizedRect(normalized, capture.image.width, capture.image.height)
        return NSRect(
            x: capture.region.minX + px.minX / capture.scale,
            y: capture.region.minY + px.minY / capture.scale,
            width: px.width / capture.scale,
            height: px.height / capture.scale
        )
    }
}
