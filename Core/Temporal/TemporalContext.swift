import Foundation

/// Single source of truth for current time across all three agents.
/// Updates on every conversation turn — agents never reference stale time.
final class TemporalContext {
    static let shared = TemporalContext()

    /// Dardan's default timezone
    private let defaultTimeZone = TimeZone(identifier: "America/Los_Angeles")!

    private init() {}

    /// Get formatted temporal string for agent system prompts.
    /// Format: "Current date and time: [Day], [Month] [Date], [Year] at [HH:MM] [AM/PM] [Timezone]"
    func currentPrompt(timeZone: TimeZone? = nil) -> String {
        let tz = timeZone ?? defaultTimeZone
        let now = Date()

        let dayFormatter = DateFormatter()
        dayFormatter.timeZone = tz
        dayFormatter.dateFormat = "EEEE"
        let dayName = dayFormatter.string(from: now)

        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = tz
        dateFormatter.dateFormat = "MMMM d, yyyy"
        let dateStr = dateFormatter.string(from: now)

        let timeFormatter = DateFormatter()
        timeFormatter.timeZone = tz
        timeFormatter.dateFormat = "h:mm a"
        let timeStr = timeFormatter.string(from: now)

        let tzFormatter = DateFormatter()
        tzFormatter.timeZone = tz
        tzFormatter.dateFormat = "zzz"
        let tzStr = tzFormatter.string(from: now)

        return "Current date and time: \(dayName), \(dateStr) at \(timeStr) \(tzStr)"
    }

    /// Structured temporal data for programmatic use.
    func currentData(timeZone: TimeZone? = nil) -> TemporalData {
        let tz = timeZone ?? defaultTimeZone
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents(in: tz, from: now)

        return TemporalData(
            date: now,
            dayOfWeek: components.weekday ?? 1,
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            isWeekend: (components.weekday ?? 1) == 1 || (components.weekday ?? 1) == 7,
            timeZone: tz,
            prompt: currentPrompt(timeZone: tz)
        )
    }
}

struct TemporalData {
    let date: Date
    let dayOfWeek: Int
    let hour: Int
    let minute: Int
    let isWeekend: Bool
    let timeZone: TimeZone
    let prompt: String

    var isBusinessHours: Bool {
        !isWeekend && hour >= 9 && hour < 17
    }

    var isMarketOpen: Bool {
        // NYSE/NASDAQ: 6:30 AM - 1:00 PM Pacific
        !isWeekend && hour >= 6 && (hour < 13 || (hour == 6 && minute >= 30))
    }
}
