import Charts
import SwiftUI

// Charts of attention levels. Levels use their own colours and nothing else
// does; every chart also names the level in text or by shape.

private struct LevelSlice: Identifiable {
    let level: Level
    let count: Int
    var id: Level { level }
}

/// A donut of how many signals are at each level, with the total in the middle.
struct LevelDonut: View {
    let counts: [Level: Int]
    var caption: LocalizedStringKey = "signals"

    var body: some View {
        let slices = [Level.alert, .watch, .normal]
            .map { LevelSlice(level: $0, count: counts[$0, default: 0]) }
            .filter { $0.count > 0 }
        let total = slices.map(\.count).reduce(0, +)
        Chart(slices) { slice in
            SectorMark(angle: .value("Signals", slice.count), innerRadius: .ratio(0.64), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(slice.level.color.gradient)
        }
        .chartLegend(.hidden)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let frame = geometry[anchor]
                    VStack(spacing: 0) {
                        Text("\(total)")
                            .font(.title2.weight(.bold))
                            .fontDesign(.rounded)
                            .monospacedDigit()
                        Text(caption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slices.map { "\($0.count) \($0.level.label)" }.joined(separator: ", "))
    }
}

/// A legend row for level charts: symbol, name and count.
struct LevelLegend: View {
    let counts: [Level: Int]
    var levels: [Level] = [.alert, .watch, .normal]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { items }
            VStack(alignment: .leading, spacing: 6) { items }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var items: some View {
        ForEach(levels, id: \.self) { level in
            HStack(spacing: 4) {
                StatusGlyph(level, font: .caption)
                Text("\(counts[level, default: 0])")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                Text(level.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Stacked columns: signals at each level at the end of each day.
struct LevelMixColumns: View {
    let data: [DayLevelCount]

    var body: some View {
        Chart(data) { item in
            BarMark(x: .value("Day", item.day, unit: .day), y: .value("Signals", item.count), width: .ratio(0.5))
                .foregroundStyle(by: .value("Level", item.level.label))
                .cornerRadius(4)
        }
        .chartForegroundStyleScale(["Alert": Level.alert.color.gradient, "Watch": Level.watch.color.gradient,
                                    "Normal": Level.normal.color.gradient])
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(data))
    }

    static func summary(_ data: [DayLevelCount]) -> String {
        let days = Dictionary(grouping: data, by: \.day).sorted { $0.key < $1.key }
        return days.map { day, items in
            let alert = items.first { $0.level == .alert }?.count ?? 0
            return "\(day.formatted(.dateTime.weekday(.wide))): \(alert) on Alert"
        }
        .joined(separator: "; ")
    }
}

/// Health's sleep-stage style: one row per level, a bar for each stretch of
/// time the signal spent there.
struct LevelTimeline: View {
    let spans: [LevelSpan]

    var body: some View {
        Chart(spans) { span in
            RectangleMark(
                xStart: .value("From", span.start),
                xEnd: .value("To", span.end),
                y: .value("Level", span.level.label),
                height: .ratio(0.62)
            )
            .foregroundStyle(span.level.color.gradient)
            .cornerRadius(5)
        }
        .chartYScale(domain: ["Alert", "Watch", "Normal"])
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spans.map {
            "\($0.level.label) from \($0.start.formatted(date: .abbreviated, time: .shortened))"
        }.joined(separator: ", "))
    }
}
