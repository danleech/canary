import Charts
import SwiftUI

private struct ValuePoint: Identifiable {
    let index: Int
    let date: Date
    let value: Double
    let level: Level
    var id: Int { index }
}

private func valuePoints(_ history: [HistoryPoint]) -> [ValuePoint] {
    history.enumerated().compactMap { index, point in
        point.value.map { ValuePoint(index: index, date: point.date, value: $0, level: point.level) }
    }
}

/// Lower and upper bounds with a little headroom, so a smoothed line never
/// touches the edges.
private func paddedDomain(_ values: [Double]) -> ClosedRange<Double> {
    guard let low = values.min(), let high = values.max() else { return 0...1 }
    let span = high - low
    let pad = span > 0 ? span * 0.18 : max(abs(high) * 0.05, 1)
    return (low - pad)...(high + pad)
}

/// Health-style chart of a signal's key value: a smoothed line over a soft
/// gradient, a dot at each check in that check's level colour, and a callout
/// for the check you touch.
struct ValueChart: View {
    let history: [HistoryPoint]
    let tint: Color
    /// Updated while a finger is on the chart.
    @Binding var selection: Date?
    /// The check to mark, which stays after the finger lifts, as in Health.
    var highlighted: Date?

    var body: some View {
        let points = valuePoints(history)
        let domain = paddedDomain(points.map(\.value))
        let selected = (selection ?? highlighted).flatMap { date in
            points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Checked", point.date),
                    yStart: .value("Base", domain.lowerBound),
                    yEnd: .value("Value", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Checked", point.date), y: .value("Value", point.value))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(tint)
                PointMark(x: .value("Checked", point.date), y: .value("Value", point.value))
                    .symbolSize(selected?.index == point.index ? 110 : 34)
                    .foregroundStyle(point.level.color)
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ValueCallout(point: selected)
                    }
            }
        }
        .chartYScale(domain: domain)
        .chartXSelection(value: $selection)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .sensoryFeedback(.selection, trigger: selected?.index)
    }
}

private struct ValueCallout: View {
    let point: ValuePoint

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(point.value.formatted(.number.precision(.fractionLength(0...2))))
                .font(.headline)
                .fontDesign(.rounded)
            Label(point.level.label, systemImage: point.level.symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(point.level.textColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

/// The small chart in a tile: the key value as a smoothed line over a gradient
/// ending in a dot at the current level, or, with no numbers, one rounded
/// column per check in its level's colour.
struct TileChart: View {
    let history: [HistoryPoint]
    let level: Level
    let tint: Color

    var body: some View {
        let points = valuePoints(history)
        Group {
            if points.count >= 2 {
                let domain = paddedDomain(points.map(\.value))
                Chart {
                    ForEach(points) { point in
                        AreaMark(x: .value("Checked", point.date),
                                 yStart: .value("Base", domain.lowerBound),
                                 yEnd: .value("Value", point.value))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Checked", point.date), y: .value("Value", point.value))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(tint)
                    }
                    if let last = points.last {
                        PointMark(x: .value("Checked", last.date), y: .value("Value", last.value))
                            .symbolSize(36)
                            .foregroundStyle(level.color)
                    }
                }
                .chartYScale(domain: domain)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
            } else if !history.isEmpty {
                let shown = Array(history.suffix(16).enumerated())
                Chart(shown, id: \.offset) { item in
                    BarMark(x: .value("Check", String(item.offset)), y: .value("Level", 1), width: .ratio(0.7))
                        .foregroundStyle(item.element.level.color.opacity(item.element.level == .pending ? 0.35 : 0.9))
                        .cornerRadius(3)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            } else {
                Color.clear
            }
        }
        .accessibilityHidden(true)
    }
}
