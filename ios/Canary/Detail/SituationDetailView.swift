import SwiftUI

/// A situation and the signals it moves.
struct SituationDetailView: View {
    let situationID: String
    @Environment(BoardStore.self) private var store

    var body: some View {
        if let board = store.board, let situation = board.situation(situationID) {
            let signals = board.signals(inSituation: situation, at: store.now)
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
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
                        if let summary = situation.summary {
                            Text(summary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                }
                Section {
                    ForEach(signals) { signal in
                        NavigationLink(value: Route.signal(signal.id)) {
                            SignalRow(signal: signal, showsDomain: true)
                        }
                    }
                } header: {
                    Text("^[\(signals.count) Signal](inflect: true)")
                } footer: {
                    Text("A situation groups signals moved by one event. It never changes a signal's level, but signals in one situation count once per domain in the World State index.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollRevealedTitle(situation.name, threshold: 80)
        } else {
            ContentUnavailableView("Situation Has Ended", systemImage: "checkmark.circle",
                                   description: Text("This situation is no longer on the board."))
        }
    }
}
