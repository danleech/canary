import Charts
import SwiftUI

/// What makes up the World State index, each part charted to fit its data: the
/// trend as a smoothed line, today's level mix as a donut, the mix by day as
/// stacked columns, domain scores as bars, how levels were set as a donut, and
/// how long signals have held their level as a scatter.
struct WorldStateDetailView: View {
    @Environment(BoardStore.self) private var store

    var body: some View {
        if let board = store.board {
            let band = board.status.world.bandKind
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    WorldHeroTile(board: board, isLink: false)
                    AdaptiveColumns {
                        TrendTile(points: board.worldTrend, band: band)
                        LevelMixTile(board: board)
                        BasisTile(board: board)
                    } trailing: {
                        DomainScoresTile(board: board)
                        LevelAgeTile(board: board)
                        MethodTile()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .debugScrollable()
            .background { WashedBackground(tint: band.color) }
            .navigationTitle("World State")
            .navigationBarTitleDisplayMode(.inline)
            .opensLinksInApp()
        }
    }
}

/// The index over time.
private struct TrendTile: View {
    let points: [WorldPoint]
    let band: WorldBand

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleHeader("Trend", systemImage: "chart.line.uptrend.xyaxis", hue: Hue(fill: band.color, text: .primary))
            if let first = points.first, let last = points.last, points.count >= 2 {
                Text(sentence(from: first.score, to: last.score, since: first.date))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                WorldTrendChart(points: points, band: band)
                    .frame(height: 170)
                Text("The index method changed on 2 November 2026, so the line starts there.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("The trend line starts after a few more checks.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .tile(tint: band.color)
    }

    private func sentence(from: Int, to: Int, since: Date) -> String {
        let day = since.formatted(.dateTime.day().month(.wide))
        if to > from { return "Up \(to - from) since \(day)." }
        if to < from { return "Down \(from - to) since \(day)." }
        return "Unchanged since \(day)."
    }
}

/// Today's level mix as a donut, and the mix at the end of each day.
private struct LevelMixTile: View {
    let board: Board
    @Environment(BoardStore.self) private var store

    var body: some View {
        let counts = board.counts(at: store.now)
        let byDay = board.dailyLevelMix(days: 7, now: store.now)
        let days = Set(byDay.map(\.day)).count
        VStack(alignment: .leading, spacing: 14) {
            ModuleHeader("Level Mix", systemImage: "chart.pie.fill", hue: Level.alert.hue)
            HStack(alignment: .center, spacing: 18) {
                LevelDonut(counts: counts)
                    .frame(width: 128, height: 128)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach([Level.alert, .watch, .normal], id: \.self) { level in
                        HStack(spacing: 6) {
                            StatusGlyph(level, font: .subheadline)
                            Text("\(counts[level, default: 0])")
                                .font(.headline)
                                .fontDesign(.rounded)
                                .monospacedDigit()
                            Text(level.label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if days >= 2 {
                Text("At the end of each day")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                LevelMixColumns(data: byDay)
                    .frame(height: 130)
            }
        }
        .tile(tint: Level.alert.color)
    }
}

/// Every domain's score as a bar in its colour.
private struct DomainScoresTile: View {
    let board: Board

    var body: some View {
        let items = board.domainScores
        VStack(alignment: .leading, spacing: 12) {
            ModuleHeader("By Domain", systemImage: "square.grid.2x2.fill", hue: Hue(fill: .indigo, text: .primary))
            if items.isEmpty {
                Text("Domain scores aren't available for this run.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                DomainBars(items: items)
                Text("Each domain's signals score 0 for Normal, 1 for Watch and 2 for Alert, scaled to 100.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tile(tint: .indigo)
    }
}

/// How levels were set: measured, published figure or AI judgement.
private struct BasisTile: View {
    let board: Board

    var body: some View {
        let counts: [Basis: Int] = [
            .measured: board.basisCount(.measured),
            .published: board.basisCount(.published),
            .judged: board.basisCount(.judged),
        ]
        VStack(alignment: .leading, spacing: 14) {
            ModuleHeader("How Levels Were Set", systemImage: "checkmark.seal.fill", hue: Basis.judged.hue)
            HStack(alignment: .center, spacing: 18) {
                BasisDonut(counts: counts)
                    .frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach([Basis.measured, .published, .judged], id: \.self) { basis in
                        HStack(spacing: 6) {
                            Image(systemName: basis.symbol)
                                .foregroundStyle(basis.hue.fill)
                                .frame(width: 18)
                            Text("\(counts[basis, default: 0])")
                                .font(.headline)
                                .fontDesign(.rounded)
                                .monospacedDigit()
                            Text(basis.label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Text("AI judgements are the assessor's reading of each run's sources against the rubric. Weigh them with more caution than measured levels.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tile(tint: Basis.judged.hue.fill)
    }
}

/// How long each signal has held its level.
private struct LevelAgeTile: View {
    let board: Board
    @Environment(BoardStore.self) private var store

    var body: some View {
        let ages = board.levelAges(now: store.now)
        let alerts = ages.filter { $0.level == .alert }
        VStack(alignment: .leading, spacing: 12) {
            ModuleHeader("How Long Levels Have Held", systemImage: "hourglass", hue: Hue(fill: .teal, text: .primary))
            if let longest = alerts.first {
                Text("The longest-held Alert is \(longest.name), for \(longest.days.formatted(.number.precision(.fractionLength(0...1)))) days.")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LevelAgeScatter(ages: ages, domains: board.domains)
            HStack(spacing: 14) {
                legend("diamond.fill", .alert)
                legend("triangle.fill", .watch)
                legend("circle.fill", .normal)
            }
            Text("Each mark is a signal. Long-running situations sit to the right; new moves sit on the left. A chronic situation at steady intensity is Watch, not Alert.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tile(tint: .teal)
    }

    private func legend(_ symbol: String, _ level: Level) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(level.color)
            Text(level.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MethodTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModuleHeader("How the Index Works", systemImage: "function", hue: Hue(fill: .gray, text: .primary))
            Text("Each signal scores 0 for Normal, 1 for Watch and 2 for Alert. Within each domain, signals in the same situation count once, at the highest level among them, so one event can't fill a domain on its own. Domain scores are averaged with equal weight and scaled from 0 to 100.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text("Calm is below 25, Unsettled 25 to 39, Strained 40 to 59, and Severe 60 or more.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("Read the Full Method", destination: AppConstants.indexMethodURL)
                .font(.subheadline.weight(.semibold))
        }
        .tile()
    }
}
