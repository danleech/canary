import SwiftUI

/// A situation and the signals it moves: a header tile with the levels of its
/// signals as a donut, then the signals as tiles.
struct SituationDetailView: View {
    let situationID: String
    @Environment(BoardStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let board = store.board, let situation = board.situation(situationID) {
            let signals = board.signals(inSituation: situation, at: store.now)
            let counts = board.counts(in: signals, at: store.now)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(situation, counts: counts)
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle("^[\(signals.count) Signal](inflect: true)")
                        SignalTileGrid(signals: signals)
                        Text("A situation groups signals moved by one event. It never changes a signal's level, but signals in one situation count once per domain in the World State index.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background { WashedBackground(tint: situation.status.color) }
            .scrollRevealedTitle(situation.name, threshold: 80)
        } else {
            ContentUnavailableView("Situation Has Ended", systemImage: "checkmark.circle",
                                   description: Text("This situation is no longer on the board."))
        }
    }

    private func header(_ situation: Situation, counts: [Level: Int]) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                StatusLabel(situation.status, font: .title3.weight(.bold))
                if let trend = situation.trend, trend != .unknown {
                    Label(trend.label, systemImage: trend.symbol)
                        .foregroundStyle(.secondary)
                }
            }
            Text(situation.name)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            layout {
                VStack(alignment: .leading, spacing: 10) {
                    if let summary = situation.summary {
                        Text(summary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LevelLegend(counts: counts)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                LevelDonut(counts: counts)
                    .frame(width: 104, height: 104)
            }
        }
        .tile(tint: situation.status.color)
        .accessibilityElement(children: .combine)
    }
}
