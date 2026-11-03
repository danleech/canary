import Foundation

/// Date and time wording, in the person's own locale and time zone.
public enum CanaryFormat {
    /// "18:02" today, "Yesterday 23:43", "2 Nov 23:43" otherwise.
    public static func when(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday \(time)")
        }
        return date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    /// "12 min ago", "3 hr ago".
    public static func ago(_ date: Date, now: Date = .now) -> String {
        if now.timeIntervalSince(date) < 60 { return String(localized: "Just now") }
        return date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }

    /// "Today", "Yesterday", or "Monday 2 November" for list section headers.
    public static func day(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    /// "for 2 days", from the time a status last changed.
    public static func duration(since date: Date, now: Date = .now) -> String {
        let seconds = max(now.timeIntervalSince(date), 60)
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = seconds >= 86_400 ? [.day] : seconds >= 3600 ? [.hour] : [.minute]
        return formatter.string(from: seconds) ?? ""
    }
}
