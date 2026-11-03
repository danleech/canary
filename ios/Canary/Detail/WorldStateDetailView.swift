import Charts
import SwiftUI

/// What makes up the World State index: the score by domain, its trend, how
/// statuses were set, and how the index is calculated.
struct WorldStateDetailView: View {
    @Environment(BoardStore.self) private var store

    var body: some View {
        if let board = store.board {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AdaptiveColumns {
                        WorldStateCard(board: board, isLink: false)
                        TrendCard(points: board.worldTrend)
                        BasisSummaryCard(board: board)
                    } trailing: {
                        DomainScoresCard(board: board)
                        MethodCard()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("World State")
            .navigationBarTitleDisplayMode(.inline)
            .opensLinksInApp()
        }
    }
}

/// Horizontal bars of each domain's 0–100 score.
private struct DomainScoresCard: View {
    let board: Board

    var body: some View {
        let scores = board.domains.compactMap { domain in
            board.status.world.byDomain?[domain.id].map { DomainScore(domain: domain, score: $0) }
        }
        VStack(alignment: .leading, spacing: 12) {
            ModuleHeader("By Domain", systemImage: "square.grid.2x2")
            if scores.isEmpty {
                Text("Domain scores aren't available for this run.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(scores, id: \.domain.id) { item in
                    NavigationLink(value: Route.domain(item.domain.id)) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(item.domain.name, systemImage: DomainStyle.symbol(for: item.domain.id))
                                    .font(.subheadline)
                                Spacer()
                                Text("\(item.score)")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                            Gauge(value: Double(item.score), in: 0...100) { EmptyView() }
                                .gaugeStyle(.linearCapacity)
                                .tint(.accentColor)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.domain.name), \(item.score) out of 100")
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
        .card()
    }
}

private struct DomainScore {
    let domain: Domain
    let score: Int
}

/// The index over time (method 2 only; the series restarted on 2 Nov 2026).
private struct TrendCard: View {
    let points: [WorldPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleHeader("Trend", systemImage: "chart.line.uptrend.xyaxis")
            if points.count >= 2 {
                Chart {
                    ForEach(WorldBand.thresholds.dropFirst(), id: \.from) { threshold in
                        RuleMark(y: .value("Band", threshold.from))
                            .foregroundStyle(threshold.band.color.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text(threshold.band.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                    }
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Time", point.date), y: .value("Score", point.score))
                            .interpolationMethod(.stepEnd)
                            .foregroundStyle(.tint)
                    }
                }
                .chartYScale(domain: 0...100)
                .frame(height: 160)
                .accessibilityLabel("World State over time, from \(points.first!.score) to \(points.last!.score)")
                Text("The index method changed on 2 November 2026, so the line starts there.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("The trend line starts after a few more checks.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

private struct BasisSummaryCard: View {
    let board: Board

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleHeader("How Levels Were Set", systemImage: "checkmark.seal")
            ForEach([Basis.measured, .published, .judged], id: \.self) { basis in
                LabeledContent {
                    Text("\(board.basisCount(basis))")
                        .monospacedDigit()
                } label: {
                    Label(basis.label, systemImage: basis.symbol)
                }
                .font(.subheadline)
            }
            Text("AI judgements are the assessor's reading of each run's sources against the rubric. Weigh them with more caution than measured levels.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }
}

private struct MethodCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModuleHeader("How the Index Works", systemImage: "function")
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
        .card()
    }
}
