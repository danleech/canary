import SwiftUI

/// Every recent status change, grouped by day, newest first.
struct ChangesView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all, pinned, escalations
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .all: "All Changes"
            case .pinned: "Pinned Signals"
            case .escalations: "Moves Up Only"
            }
        }
    }

    @Environment(BoardStore.self) private var store
    @Environment(PinStore.self) private var pins
    @Environment(Router.self) private var router
    @State private var filter: Filter = .all
    @State private var showsSettings = false

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.changesPath) {
            Group {
                if let board = store.board {
                    let changes = filtered(board.changes)
                    let days = Dictionary(grouping: changes) { Calendar.current.startOfDay(for: $0.t) }
                    let moves = board.dailyMoves(days: 14, now: store.now)
                    List {
                        if filter == .all, moves.count >= 2 {
                            Section {
                                VStack(alignment: .leading, spacing: 12) {
                                    let up = moves.map(\.up).reduce(0, +)
                                    let down = moves.map(\.down).reduce(0, +)
                                    Text("\(up) moved up and \(down) eased since \(moves[0].day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).")
                                        .font(.headline)
                                        .fixedSize(horizontal: false, vertical: true)
                                    MovesColumns(data: moves)
                                        .frame(height: 150)
                                    MovesLegend(up: up, down: down)
                                }
                                .padding(.vertical, 6)
                            } header: {
                                Text("By Day")
                            }
                        }
                        ForEach(days.keys.sorted(by: >), id: \.self) { day in
                            Section(CanaryFormat.day(day, now: store.now)) {
                                ForEach(days[day] ?? [], id: \.key) { change in
                                    NavigationLink(value: Route.signal(change.id)) {
                                        ChangeRow(change: change)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .overlay {
                        if changes.isEmpty {
                            ContentUnavailableView(
                                filter == .pinned ? "No Changes to Pinned Signals" : "No Recent Changes",
                                systemImage: "clock",
                                description: Text("Levels change only when evidence clearly crosses a threshold, so quiet days are normal.")
                            )
                        }
                    }
                }
            }
            .navigationTitle("Changes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Show", selection: $filter) {
                            ForEach(Filter.allCases) { Text($0.label).tag($0) }
                        }
                    } label: {
                        Label("Filter", systemImage: filter == .all
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                SettingsToolbarItem(isPresented: $showsSettings)
            }
            .refreshable { await store.refresh() }
            .routeDestinations()
            .sheet(isPresented: $showsSettings) { SettingsView() }
        }
    }

    private func filtered(_ changes: [StatusChange]) -> [StatusChange] {
        switch filter {
        case .all: changes
        case .pinned: changes.filter { pins.isPinned($0.id) }
        case .escalations: changes.filter(\.isEscalation)
        }
    }
}
