import Foundation

/// Persists reading stats across sessions; tracks a daily counter that
/// resets when the calendar day changes.
final class StatsStore: ObservableObject {
    static let shared = StatsStore()

    @Published private(set) var todayWords = 0
    @Published private(set) var todaySeconds = 0.0
    @Published private(set) var totalWords = 0

    private let defaults = UserDefaults.standard

    private init() {
        rollOverDayIfNeeded()
        todayWords = defaults.integer(forKey: "statsTodayWords")
        todaySeconds = defaults.double(forKey: "statsTodaySeconds")
        totalWords = defaults.integer(forKey: "statsTotalWords")
    }

    func record(_ stats: ReadingStats) {
        guard stats.wordsRead > 0 else { return }
        rollOverDayIfNeeded()
        todayWords += stats.wordsRead
        todaySeconds += stats.elapsed
        totalWords += stats.wordsRead
        defaults.set(todayWords, forKey: "statsTodayWords")
        defaults.set(todaySeconds, forKey: "statsTodaySeconds")
        defaults.set(totalWords, forKey: "statsTotalWords")
    }

    /// e.g. "Today: 3,240 words · avg 312 wpm"
    var todaySummary: String? {
        guard todayWords > 0 else { return nil }
        var summary = "Today: \(todayWords.formatted()) words"
        if todaySeconds > 30 {
            let wpm = Int(Double(todayWords) / todaySeconds * 60)
            summary += " · avg \(wpm) wpm"
        }
        return summary
    }

    private var dayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func rollOverDayIfNeeded() {
        let today = dayKey
        if defaults.string(forKey: "statsDay") != today {
            defaults.set(today, forKey: "statsDay")
            defaults.set(0, forKey: "statsTodayWords")
            defaults.set(0.0, forKey: "statsTodaySeconds")
            todayWords = 0
            todaySeconds = 0
        }
    }
}
