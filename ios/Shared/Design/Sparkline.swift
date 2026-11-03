import Charts
import SwiftUI

/// Stocks-style mini chart of a signal's key value, ending in a dot coloured by
/// the current level. Falls back to a strip of status ticks when the signal has
/// no numeric series.
public struct Sparkline: View {
    let points: [HistoryPoint]
    let level: Level

    public init(points: [HistoryPoint], level: Level) {
        self.points = points
        self.level = level
    }

    public var body: some View {
        let values = points.enumerated().compactMap { index, point in
            point.value.map { SparkPoint(index: index, date: point.date, value: $0) }
        }
        Group {
            if values.count >= 2 {
                Chart {
                    ForEach(values) { point in
                        LineMark(x: .value("Time", point.date), y: .value("Value", point.value))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(Color.secondary)
                    }
                    if let last = values.last {
                        PointMark(x: .value("Time", last.date), y: .value("Value", last.value))
                            .symbolSize(28)
                            .foregroundStyle(level.color)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartLegend(.hidden)
            } else if !points.isEmpty {
                StatusStrip(points: points)
            } else {
                Color.clear
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SparkPoint: Identifiable {
    let index: Int
    let date: Date
    let value: Double
    var id: Int { index }
}

/// One small bar per check, coloured by level: the board's status timeline.
public struct StatusStrip: View {
    let points: [HistoryPoint]
    var maxCount = 24

    public init(points: [HistoryPoint], maxCount: Int = 24) {
        self.points = points
        self.maxCount = maxCount
    }

    public var body: some View {
        let shown = Array(points.suffix(maxCount))
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, point in
                Capsule()
                    .fill(point.level.color.opacity(point.level == .pending ? 0.4 : 1))
                    .frame(maxWidth: 6)
                    .frame(height: 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .accessibilityHidden(true)
    }
}
