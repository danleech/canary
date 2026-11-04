import Charts
import SwiftUI

// Charts of the whole board. Directions, domains and bases use colours outside
// red, orange and green, which belong to attention levels.

private struct MoveBar: Identifiable {
    let day: Date
    let direction: String
    let value: Int
    var id: String { "\(day.timeIntervalSince1970)-\(direction)" }
}

/// Diverging columns: moves to more attention above the line, easings below.
struct MovesColumns: View {
    let data: [DayMoves]

    static let upColor = Color.pink
    static let downColor = Color.cyan

    var body: some View {
        let bars = data.flatMap { day in
            [MoveBar(day: day.day, direction: "Moved up", value: day.up),
             MoveBar(day: day.day, direction: "Eased", value: -day.down)]
        }
        Chart {
            ForEach(bars) { bar in
                BarMark(x: .value("Day", bar.day, unit: .day), y: .value("Changes", bar.value), width: .ratio(0.55))
                    .foregroundStyle(by: .value("Direction", bar.direction))
                    .cornerRadius(4)
            }
            RuleMark(y: .value("None", 0))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartForegroundStyleScale(["Moved up": Self.upColor.gradient, "Eased": Self.downColor.gradient])
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let count = value.as(Int.self) { Text("\(abs(count))") }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(data.map {
            "\($0.day.formatted(.dateTime.weekday(.wide))): \($0.up) moved up, \($0.down) eased"
        }.joined(separator: "; "))
    }
}

/// A legend for `MovesColumns`.
struct MovesLegend: View {
    let up: Int
    let down: Int

    var body: some View {
        HStack(spacing: 14) {
            item(color: MovesColumns.upColor, symbol: "arrow.up", count: up, label: "moved up")
            item(color: MovesColumns.downColor, symbol: "arrow.down", count: down, label: "eased")
        }
        .accessibilityElement(children: .combine)
    }

    private func item(color: Color, symbol: String, count: Int, label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Horizontal bars of domain scores, each in its domain's colour.
struct DomainBars: View {
    let items: [DomainScoreItem]
    var barHeight: CGFloat = 26

    var body: some View {
        Chart(items) { item in
            BarMark(x: .value("Score", item.score),
                    y: .value("Domain", DomainStyle.shortName(for: item.domain.id, fallback: item.domain.name)),
                    height: .ratio(0.68))
                .foregroundStyle(DomainStyle.color(for: item.domain.id).gradient)
                .cornerRadius(6)
                .annotation(position: .trailing, spacing: 6) {
                    Text("\(item.score)")
                        .font(.caption.weight(.semibold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
        }
        .chartXScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
            }
        }
        .frame(height: CGFloat(items.count) * barHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.map { "\($0.domain.name) \($0.score)" }.joined(separator: ", "))
    }
}

private struct BasisSlice: Identifiable {
    let basis: Basis
    let count: Int
    var id: Basis { basis }
}

/// A donut of how levels were set: measured, published figure or AI judgement.
struct BasisDonut: View {
    let counts: [Basis: Int]

    var body: some View {
        let slices = [Basis.measured, .published, .judged]
            .map { BasisSlice(basis: $0, count: counts[$0, default: 0]) }
            .filter { $0.count > 0 }
        Chart(slices) { slice in
            SectorMark(angle: .value("Signals", slice.count), innerRadius: .ratio(0.62), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(slice.basis.hue.fill.gradient)
        }
        .chartLegend(.hidden)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slices.map { "\($0.count) \($0.basis.label)" }.joined(separator: ", "))
    }
}

/// The World State index over time: a smoothed line over a gradient in the
/// band's colours, with the band edges marked.
struct WorldTrendChart: View {
    let points: [WorldPoint]
    let band: WorldBand

    var body: some View {
        Chart {
            ForEach(WorldBand.thresholds.dropFirst(), id: \.from) { threshold in
                RuleMark(y: .value("Band", threshold.from))
                    .foregroundStyle(threshold.band.color.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text(threshold.band.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                AreaMark(x: .value("Time", point.date), y: .value("Score", point.score))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [band.color.opacity(0.35), band.color.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", point.date), y: .value("Score", point.score))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(LinearGradient(colors: band.ringColors, startPoint: .leading, endPoint: .trailing))
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 25, 50, 75, 100]) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("World State over time, from \(points.first?.score ?? 0) to \(points.last?.score ?? 0)")
    }
}

private struct AgeDot: Identifiable {
    let age: LevelAge
    let row: Double
    var id: String { age.id }
}

/// A scatter of how long each signal has held its level (across) by domain
/// (down), shaped and coloured by level. Long-held Alerts are chronic; new
/// ones sit on the left (rule 8: chronic is not new).
struct LevelAgeScatter: View {
    let ages: [LevelAge]
    let domains: [Domain]

    var body: some View {
        // First domain at the top: rows count up from the bottom of the chart.
        let order = Array(domains.reversed())
        let rows = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element.id, $0.offset) })
        let dots = ages.enumerated().compactMap { index, age -> AgeDot? in
            guard let row = rows[age.domain] else { return nil }
            // A small, repeatable offset so signals at the same age stay visible.
            let jitter = (Double((index * 37) % 7) - 3) * 0.07
            return AgeDot(age: age, row: Double(row) + jitter)
        }
        let maxDays = max(ages.map(\.days).max() ?? 1, 1)
        Chart(dots) { dot in
            PointMark(x: .value("Days at level", dot.age.days), y: .value("Domain", dot.row))
                .foregroundStyle(by: .value("Level", dot.age.level.label))
                .symbol(by: .value("Level", dot.age.level.label))
                .symbolSize(46)
                .opacity(0.85)
        }
        .chartForegroundStyleScale(["Alert": Level.alert.color, "Watch": Level.watch.color, "Normal": Level.normal.color])
        .chartSymbolScale(["Alert": BasicChartSymbolShape.diamond,
                           "Watch": BasicChartSymbolShape.triangle,
                           "Normal": BasicChartSymbolShape.circle])
        .chartLegend(.hidden)
        .chartXScale(domain: 0...(maxDays * 1.08))
        .chartYScale(domain: -0.6...(Double(max(domains.count - 1, 0)) + 0.6))
        .chartYAxis {
            AxisMarks(values: Array(order.indices).map(Double.init)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let index = value.as(Double.self), order.indices.contains(Int(index)) {
                        let domain = order[Int(index)]
                        Text(DomainStyle.shortName(for: domain.id, fallback: domain.name))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let days = value.as(Double.self) { Text("\(Int(days.rounded()))d") }
                }
            }
        }
        .frame(height: CGFloat(domains.count) * 26 + 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Days each signal has held its level. Longest: \(ages.first.map { "\($0.name), \(Int($0.days)) days at \($0.level.label)" } ?? "none").")
    }
}
