import AppKit
import SwiftUI

enum ReadingMode: String, CaseIterable, Identifiable {
    case focus = "Focus"
    case guide = "Guide"

    var id: String { rawValue }

    var help: String {
        switch self {
        case .focus: return "Freeze the screen, dim everything except the line being read"
        case .guide: return "Move the highlight over the live screen"
        }
    }
}

enum GuideStyle: String, CaseIterable, Identifiable {
    case wordHighlight = "Word highlight"
    case underline = "Underline"
    case ruler = "Line ruler"

    var id: String { rawValue }
}

enum GuideColor: String, CaseIterable, Identifiable {
    case orange = "Orange"
    case green = "Green"
    case blue = "Blue"
    case pink = "Pink"

    var id: String { rawValue }

    var nsColor: NSColor {
        switch self {
        case .orange: return .systemOrange
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .pink: return .systemPink
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

/// UserDefaults-backed settings shared by the widget UI and (later) the reading engine.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("wpm") var wpm: Double = 300
    @AppStorage("chunkSize") var chunkSize: Int = 1
    @AppStorage("readingMode") var readingModeRaw: String = ReadingMode.focus.rawValue
    @AppStorage("guideStyle") var guideStyleRaw: String = GuideStyle.wordHighlight.rawValue
    @AppStorage("guideColor") var guideColorRaw: String = GuideColor.orange.rawValue
    @AppStorage("dimOpacity") var dimOpacity: Double = 0.55
    @AppStorage("readAloud") var readAloud: Bool = false

    var guideColor: GuideColor {
        get { GuideColor(rawValue: guideColorRaw) ?? .orange }
        set { guideColorRaw = newValue.rawValue }
    }

    var readingMode: ReadingMode {
        get { ReadingMode(rawValue: readingModeRaw) ?? .focus }
        set { readingModeRaw = newValue.rawValue }
    }

    var guideStyle: GuideStyle {
        get { GuideStyle(rawValue: guideStyleRaw) ?? .wordHighlight }
        set { guideStyleRaw = newValue.rawValue }
    }

    static let wpmRange: ClosedRange<Double> = 100...800

    /// Honesty indicator from the research: comprehension holds to ~400,
    /// 400-600 is skimming territory, beyond that isn't reading.
    static func paceColor(for wpm: Double) -> Color {
        switch wpm {
        case ..<400: return .green
        case ..<600: return .orange
        default: return .red
        }
    }

    static func paceLabel(for wpm: Double) -> String {
        switch wpm {
        case ..<400: return "reading"
        case ..<600: return "skimming"
        default: return "scanning"
        }
    }
}
