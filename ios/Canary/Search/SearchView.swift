import SwiftUI

/// Search across signals and situations. Before typing, suggests domains and
/// what's on Alert.
struct SearchView: View {
    @Environment(BoardStore.self) private var store
    @Environment(Router.self) private var router
    private var query: String { router.searchQuery }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.searchPath) {
            Group {
                if let board = store.board {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        suggestions(board)
                    } else {
                        results(board)
                    }
                }
            }
            .navigationTitle("Search")
            .routeDestinations()
        }
    }

    private func suggestions(_ board: Board) -> some View {
        List {
            Section("Domains") {
                ForEach(board.domains) { domain in
                    NavigationLink(value: Route.domain(domain.id)) {
                        Label(domain.name, systemImage: DomainStyle.symbol(for: domain.id))
                    }
                }
            }
            Section("Levels") {
                ForEach([Level.alert, .watch, .normal], id: \.self) { level in
                    NavigationLink(value: Route.level(level)) {
                        Label {
                            Text("On \(level.label)")
                        } icon: {
                            StatusGlyph(level)
                        }
                        .badge(board.counts(at: store.now)[level, default: 0])
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func results(_ board: Board) -> some View {
        let signals = board.search(query, at: store.now)
        let situations = board.situations.filter {
            $0.name.localizedCaseInsensitiveContains(query) || ($0.summary ?? "").localizedCaseInsensitiveContains(query)
        }
        return List {
            if !signals.isEmpty {
                Section("Signals") {
                    ForEach(signals) { signal in
                        NavigationLink(value: Route.signal(signal.id)) {
                            SignalRow(signal: signal, showsDomain: true)
                        }
                    }
                }
            }
            if !situations.isEmpty {
                Section("Situations") {
                    ForEach(situations) { situation in
                        NavigationLink(value: Route.situation(situation.id)) {
                            HStack(spacing: 12) {
                                StatusGlyph(situation.status)
                                Text(situation.name)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(situation.name), \(situation.status.label)")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if signals.isEmpty, situations.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}
