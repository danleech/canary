import SwiftUI

/// Health-style Browse: domains in a list. At regular width (iPhone Duo's inner
/// display, Pro Max in landscape) it becomes a split view, showing the domains
/// beside the selected domain's signals — two levels of the same hierarchy.
struct BrowseView: View {
    @Environment(BoardStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showsSettings = false

    var body: some View {
        @Bindable var router = router
        // Selecting from Browse's own list starts that item's stack afresh; folding
        // or unfolding iPhone Duo (Router.adapt) carries the open stack across.
        let selection = Binding(get: { router.browseSelection }, set: { router.selectBrowse($0) })
        NavigationSplitView {
            BrowseSidebar(selection: selection)
                .navigationTitle("Browse")
                .toolbar { SettingsToolbarItem(isPresented: $showsSettings) }
        } detail: {
            NavigationStack(path: $router.browsePath) {
                Group {
                    switch router.browseSelection {
                    case .allSignals: AllSignalsView()
                    case .situations: SituationListView()
                    case .domain(let id): DomainView(domainID: id)
                    case nil:
                        ContentUnavailableView("Choose a Domain", systemImage: "square.grid.2x2",
                                               description: Text("Pick a domain to see its signals."))
                    }
                }
                .routeDestinations()
            }
            .id(router.browseSelection)
        }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .onAppear {
            // Side by side, show something in the detail column from the start.
            if horizontalSizeClass == .regular, router.browseSelection == nil {
                router.browseSelection = .allSignals
            }
        }
    }
}

private struct BrowseSidebar: View {
    @Binding var selection: BrowseSelection?
    @Environment(BoardStore.self) private var store

    var body: some View {
        if let board = store.board {
            List(selection: $selection) {
                Section {
                    NavigationLink(value: BrowseSelection.allSignals) {
                        Label("All Signals", systemImage: "list.bullet")
                            .badge(board.signals.count)
                    }
                    NavigationLink(value: BrowseSelection.situations) {
                        Label("Situations", systemImage: "point.3.connected.trianglepath.dotted")
                            .badge(board.situations.count)
                    }
                }
                Section("Domains") {
                    ForEach(board.domains) { domain in
                        NavigationLink(value: BrowseSelection.domain(domain.id)) {
                            DomainRow(domain: domain, board: board)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await store.refresh() }
        }
    }
}

/// Domain name with its counts of Alert and Watch signals.
private struct DomainRow: View {
    let domain: Domain
    let board: Board
    @Environment(BoardStore.self) private var store

    var body: some View {
        let counts = board.counts(in: board.signals(inDomain: domain.id, at: store.now), at: store.now)
        HStack(spacing: 12) {
            Image(systemName: DomainStyle.symbol(for: domain.id))
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(domain.name)
                    .font(.body)
                HStack(spacing: 10) {
                    ForEach([Level.alert, .watch, .normal], id: \.self) { level in
                        if let n = counts[level], n > 0 {
                            HStack(spacing: 3) {
                                StatusGlyph(level, font: .caption)
                                Text("\(n)")
                                    .font(.caption.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(domain.name). \(counts[.alert, default: 0]) Alert, \(counts[.watch, default: 0]) Watch, \(counts[.normal, default: 0]) Normal.")
    }
}

// MARK: - Signal lists

/// A domain's signals, grouped by level.
struct DomainView: View {
    let domainID: String
    @Environment(BoardStore.self) private var store

    var body: some View {
        if let board = store.board {
            let signals = board.signals(inDomain: domainID, at: store.now)
            GroupedSignalList(signals: signals, header: domainHeader(board))
                .navigationTitle(board.domainName(domainID))
        }
    }

    private func domainHeader(_ board: Board) -> AnyView? {
        guard let score = board.status.world.byDomain?[domainID] else { return nil }
        return AnyView(
            HStack {
                Text("Domain score")
                Spacer()
                Text("\(score) / 100")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        )
    }
}

/// Every signal, grouped by level.
struct AllSignalsView: View {
    @Environment(BoardStore.self) private var store

    var body: some View {
        if let board = store.board {
            GroupedSignalList(signals: board.sorted(board.signals, at: store.now), showsDomain: true)
                .navigationTitle("All Signals")
        }
    }
}

/// Signals at one level, e.g. everything on Alert.
struct LevelListView: View {
    let level: Level
    @Environment(BoardStore.self) private var store

    var body: some View {
        if let board = store.board {
            let signals = board.signals(withLevel: level, at: store.now)
            List {
                Section {
                    ForEach(signals) { signal in
                        NavigationLink(value: Route.signal(signal.id)) {
                            SignalRow(signal: signal, showsDomain: true)
                        }
                    }
                } footer: {
                    Text(level.meaning)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("On \(level.label)")
            .overlay {
                if signals.isEmpty {
                    ContentUnavailableView("Nothing on \(level.label)", systemImage: level.symbol)
                }
            }
        }
    }
}

/// A list sectioned by level: Alert, Watch, Normal, then Stale and Pending.
struct GroupedSignalList: View {
    let signals: [Signal]
    var showsDomain = false
    var header: AnyView? = nil

    @Environment(BoardStore.self) private var store

    var body: some View {
        let groups = Dictionary(grouping: signals) { $0.level(at: store.now) }
        List {
            if let header {
                Section { header }
            }
            ForEach(Level.allCases, id: \.self) { level in
                if let items = groups[level], !items.isEmpty {
                    Section {
                        ForEach(items) { signal in
                            NavigationLink(value: Route.signal(signal.id)) {
                                SignalRow(signal: signal, showsDomain: showsDomain)
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            StatusGlyph(level, font: .footnote)
                            Text("\(level.label) · \(items.count)")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.refresh() }
    }
}

/// Every situation, most serious first.
struct SituationListView: View {
    @Environment(BoardStore.self) private var store

    var body: some View {
        if let board = store.board {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Situations group signals moved by one event. They never change a signal's level.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    let sorted = board.situations.sorted { $0.status.rank < $1.status.rank }
                    ForEach(sorted) { situation in
                        NavigationLink(value: Route.situation(situation.id)) {
                            SituationCard(situation: situation)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Situations")
        }
    }
}
