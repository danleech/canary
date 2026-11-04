import Foundation

// Figures derived from the board for charts: how the level mix has moved day by
// day, how many signals moved up or eased, and how long each signal has held its
// level. All of it comes from the published check history; nothing is estimated.

/// Signals at one level at the end of one day.
public struct DayLevelCount: Hashable, Identifiable, Sendable {
    public let day: Date
    public let level: Level
    public let count: Int
    public var id: String { "\(day.timeIntervalSince1970)-\(level.rawValue)" }
}

/// Level changes on one day: moves to a higher level of attention, and easings.
public struct DayMoves: Hashable, Identifiable, Sendable {
    public let day: Date
    public let up: Int
    public let down: Int
    public var id: Date { day }
}

/// How long a signal has held its current level.
public struct LevelAge: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let domain: String
    public let level: Level
    public let days: Double
}

/// A domain and its 0–100 score in the World State index.
public struct DomainScoreItem: Hashable, Identifiable, Sendable {
    public let domain: Domain
    public let score: Int
    public var id: String { domain.id }
}

/// One stretch of time a signal spent at a level, for a timeline.
public struct LevelSpan: Hashable, Identifiable, Sendable {
    public let start: Date
    public let end: Date
    public let level: Level
    public var id: Date { start }
}

extension Board {
    static let assessed: Set<Level> = [.alert, .watch, .normal]

    /// Signals at Alert, Watch and Normal at the end of each day, for the last
    /// `days` days that have any history. Today counts up to `now`.
    public func dailyLevelMix(days: Int = 14, now: Date = .now, calendar: Calendar = .current) -> [DayLevelCount] {
        let series = history.mapValues { $0.sorted { $0.date < $1.date } }
        var result: [DayLevelCount] = []
        for day in Self.days(back: days, from: now, calendar: calendar) {
            let end = min(calendar.date(byAdding: .day, value: 1, to: day) ?? now, now)
            var counts: [Level: Int] = [:]
            for points in series.values {
                guard let last = points.last(where: { $0.date < end }), Self.assessed.contains(last.level) else { continue }
                counts[last.level, default: 0] += 1
            }
            guard !counts.isEmpty else { continue }
            for level in [Level.alert, .watch, .normal] {
                result.append(DayLevelCount(day: day, level: level, count: counts[level, default: 0]))
            }
        }
        return result
    }

    /// Level changes per day over the last `days` days, from consecutive checks
    /// of each signal. Days before the history starts are left out.
    public func dailyMoves(days: Int = 14, now: Date = .now, calendar: Calendar = .current) -> [DayMoves] {
        var up: [Date: Int] = [:]
        var down: [Date: Int] = [:]
        var firstDay: Date?
        for points in history.values {
            let sorted = points.sorted { $0.date < $1.date }.filter { Self.assessed.contains($0.level) }
            if let first = sorted.first?.date {
                let day = calendar.startOfDay(for: first)
                firstDay = min(firstDay ?? day, day)
            }
            for (previous, current) in zip(sorted, sorted.dropFirst()) where previous.level != current.level {
                let day = calendar.startOfDay(for: current.date)
                if current.level.rank < previous.level.rank {
                    up[day, default: 0] += 1
                } else {
                    down[day, default: 0] += 1
                }
            }
        }
        guard let firstDay else { return [] }
        return Self.days(back: days, from: now, calendar: calendar)
            .filter { $0 >= firstDay }
            .map { DayMoves(day: $0, up: up[$0, default: 0], down: down[$0, default: 0]) }
    }

    /// How long each assessed signal has held its current level, longest first.
    public func levelAges(now: Date = .now) -> [LevelAge] {
        signals.compactMap { signal in
            let level = signal.level(at: now)
            guard Self.assessed.contains(level), let changed = signal.changedAt else { return nil }
            return LevelAge(id: signal.id, name: signal.name, domain: signal.domain, level: level,
                            days: max(now.timeIntervalSince(changed) / 86_400, 0))
        }
        .sorted { $0.days > $1.days }
    }

    /// Domain scores, highest first.
    public var domainScores: [DomainScoreItem] {
        domains.compactMap { domain in
            status.world.byDomain?[domain.id].map { DomainScoreItem(domain: domain, score: $0) }
        }
        .sorted { $0.score > $1.score }
    }

    /// A signal's levels as continuous stretches, merging repeated checks at the
    /// same level. The last stretch runs to `now`.
    public func levelSpans(for id: String, now: Date = .now) -> [LevelSpan] {
        let points = history(for: id).filter { Self.assessed.contains($0.level) }
        var spans: [LevelSpan] = []
        for (index, point) in points.enumerated() {
            let end = index + 1 < points.count ? points[index + 1].date : max(now, point.date)
            if let last = spans.last, last.level == point.level {
                spans[spans.count - 1] = LevelSpan(start: last.start, end: end, level: last.level)
            } else {
                spans.append(LevelSpan(start: point.date, end: end, level: point.level))
            }
        }
        return spans
    }

    /// The first `count` days ending today, oldest first, as start-of-day dates.
    static func days(back count: Int, from now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<max(count, 1)).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }
}
