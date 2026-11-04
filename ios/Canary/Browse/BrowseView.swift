import SwiftUI

/// Browse, as tiles: every signal, the situations, and one tile per domain in
/// its colour with its score and level mix. On iPhone Duo's inner display the
/// same items are listed in the sidebar instead (see RootView).
struct BrowseView: View {
    @Environment(BoardStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsSettings = false

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.browsePath) {
            ScrollView {
                if let board = store.board {
                    VStack(alignment: .leading, spacing: 22) {
                        overview(board)
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle("Domains")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 320 : 158),
                                                         spacing: 12, alignment: .top)], spacing: 12) {
                                ForEach(board.domains) { domain in
                                    NavigationLink(value: Route.domain(domain.id)) {
                                        DomainTile(domain: domain, board: board)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .background { WashedBackground(tint: .indigo) }
            .navigationTitle("Browse")
            .toolbar { SettingsToolbarItem(isPresented: $showsSettings) }
            .refreshable { await store.refresh() }
            .routeDestinations()
            .sheet(isPresented: $showsSettings) { SettingsView() }
        }
    }

    private func overview(_ board: Board) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            NavigationLink(value: Route.allSignals) {
                OverviewTile(title: "All Signals", systemImage: "list.bullet", color: .blue,
                             count: board.signals.count, counts: board.counts(at: store.now))
            }
            .buttonStyle(.plain)
            NavigationLink(value: Route.situations) {
                OverviewTile(title: "Situations", systemImage: "point.3.connected.trianglepath.dotted", color: .purple,
                             count: board.situations.count,
                             counts: Dictionary(grouping: board.situations, by: \.status).mapValues(\.count))
            }
            .buttonStyle(.plain)
        }
    }
}

/// A wide tile at the top of Browse: an icon, a title and a count.
private struct OverviewTile: View {
    let title: LocalizedStringKey
    let systemImage: String
    let color: Color
    let count: Int
    let counts: [Level: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                IconBadge(systemImage: systemImage, color: color)
                Spacer()
                Text("\(count)")
                    .font(.title.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
            }
            Text(title)
                .font(.headline)
            LevelBar(counts: counts, height: 6)
        }
        .tile(tint: color, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue("\(count)")
        .accessibilityAddTraits(.isButton)
    }
}

/// A domain as a tile, in its colour: icon, name, score and level mix.
private struct DomainTile: View {
    let domain: Domain
    let board: Board
    @Environment(BoardStore.self) private var store
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 150

    var body: some View {
        let hue = DomainStyle.hue(for: domain.id)
        let counts = board.counts(in: board.signals(inDomain: domain.id, at: store.now), at: store.now)
        let score = board.status.world.byDomain?[domain.id]
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                IconBadge(systemImage: DomainStyle.symbol(for: domain.id), color: hue.fill)
                Spacer()
                if let score {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(score)")
                            .font(.title2.weight(.bold))
                            .fontDesign(.rounded)
                            .monospacedDigit()
                        Text("score")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text(domain.name)
                .font(.headline)
                .foregroundStyle(hue.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            LevelBar(counts: counts, height: 7)
            HStack(spacing: 10) {
                ForEach([Level.alert, .watch, .normal], id: \.self) { level in
                    if let n = counts[level], n > 0 {
                        HStack(spacing: 3) {
                            StatusGlyph(level, font: .caption)
                            Text("\(n)")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
        .tile(tint: hue.fill, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(domain.name)\(score.map { ", score \($0)" } ?? ""). \(counts[.alert, default: 0]) Alert, \(counts[.watch, default: 0]) Watch, \(counts[.normal, default: 0]) Normal.")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Signal lists

/// A domain, as Health shows a category: a header tile with its score and
/// level mix, then its signals as tiles, most attention first.
struct DomainView: View {
    let domainID: String
    @Environment(BoardStore.self) private var store

    var body: some View {
        if let board = store.board {
            let signals = board.signals(inDomain: domainID, at: store.now)
            let hue = DomainStyle.hue(for: domainID)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    DomainHeaderTile(domainID: domainID, board: board, signals: signals)
                    ForEach([Level.alert, .watch, .normal, .stale, .pending], id: \.self) { level in
                        let group = signals.filter { $0.level(at: store.now) == level }
                        if !group.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 6) {
                                    StatusGlyph(level, font: .title3)
                                    Text("\(level.label) · \(group.count)")
                                        .font(.title3.weight(.bold))
                                        .accessibilityAddTraits(.isHeader)
                                }
                                .padding(.horizontal, 4)
                                SignalTileGrid(signals: group, showsDomain: false)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background { WashedBackground(tint: hue.fill) }
            .navigationTitle(board.domainName(domainID))
            .refreshable { await store.refresh() }
        }
    }
}

private struct DomainHeaderTile: View {
    let domainID: String
    let board: Board
    let signals: [Signal]
    @Environment(BoardStore.self) private var store

    var body: some View {
        let hue = DomainStyle.hue(for: domainID)
        let counts = board.counts(in: signals, at: store.now)
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                IconBadge(systemImage: DomainStyle.symbol(for: domainID), color: hue.fill, size: 40)
                if let score = board.status.world.byDomain?[domainID] {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(score)")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .monospacedDigit()
                        Text("/ 100")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("Domain score in the World State index")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LevelLegend(counts: counts)
            }
            Spacer(minLength: 0)
            LevelDonut(counts: counts)
                .frame(width: 110, height: 110)
        }
        .tile(tint: hue.fill)
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
            .background { WashedBackground(tint: .purple) }
            .navigationTitle("Situations")
        }
    }
}
