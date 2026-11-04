import SwiftUI

/// The first tab, modelled on Health's Summary: the World State, pinned signals
/// as tiles, Highlights with charts, what's on Alert, recent changes and the
/// situations driving them.
struct SummaryView: View {
    @Environment(BoardStore.self) private var store
    @Environment(Router.self) private var router
    @State private var showsSettings = false

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.summaryPath) {
            ScrollView {
                if let board = store.board {
                    VStack(alignment: .leading, spacing: 24) {
                        if let message = store.errorMessage {
                            OfflineBanner(message: message)
                        }
                        NavigationLink(value: Route.world) {
                            WorldHeroTile(board: board)
                        }
                        .buttonStyle(.plain)
                        PinnedSection(board: board)
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle("Highlights")
                            AdaptiveColumns(minColumnWidth: 330) {
                                AttentionHighlight(board: board)
                                DomainsHighlight(board: board)
                            } trailing: {
                                MovesHighlight(board: board)
                                ChangedSection(board: board)
                            }
                        }
                        AdaptiveColumns(minColumnWidth: 330) {
                            AlertNowSection(board: board)
                        } trailing: {
                            SituationsSection(board: board)
                        }
                        AboutFooter(board: board)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .debugScrollable()
            .background {
                WashedBackground(tint: (store.board?.status.world.bandKind ?? .unknown).color)
            }
            .navigationTitle("Summary")
            .toolbar { SettingsToolbarItem(isPresented: $showsSettings) }
            .refreshable { await store.refresh() }
            .routeDestinations()
            .sheet(isPresented: $showsSettings) { SettingsView() }
        }
    }
}

/// Shown when a refresh fails but a saved board is on screen.
private struct OfflineBanner: View {
    let message: String
    @Environment(BoardStore.self) private var store

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Showing the last saved board")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Retry") { Task { await store.refresh() } }
                .font(.subheadline.weight(.semibold))
        }
        .tile(padding: 12)
    }
}

// MARK: - World State

/// Weather-style hero: the index on a pastel mesh gradient in the band's
/// colours, an Activity-style ring, and the level counts on Liquid Glass.
struct WorldHeroTile: View {
    let board: Board
    var showsHeadline = true
    var isLink = true

    @Environment(BoardStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 68
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 112

    var body: some View {
        let world = board.status.world
        let band = world.bandKind
        let counts = board.counts(at: store.now)
        let levels: [Level] = counts[.stale, default: 0] > 0 ? [.alert, .watch, .normal, .stale] : [.alert, .watch, .normal]
        let scoreLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("World State", systemImage: "globe.europe.africa.fill")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if isLink {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            scoreLayout {
                VStack(alignment: .leading, spacing: 0) {
                    Text(world.score.map(String.init) ?? "–")
                        .font(.system(size: scoreSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(band.rawValue)
                        .font(.title2.weight(.bold))
                        .fontDesign(.rounded)
                    Text("out of 100")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                ScoreRing(score: world.score, band: band, lineWidth: 16)
                    .frame(width: ringSize, height: ringSize)
                    .overlay {
                        Image(systemName: "globe.europe.africa.fill")
                            .font(.system(size: ringSize * 0.3))
                            .foregroundStyle(band.color.gradient)
                            .accessibilityHidden(true)
                    }
            }
            if showsHeadline, let headline = board.status.headline {
                Text(headline)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // One row of chips; a column only at accessibility text sizes.
            let chipLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 6))
            GlassEffectContainer(spacing: 6) {
                chipLayout { chips(levels, counts) }
            }
            BoardFreshnessText()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BandMeshBackground(band: band)
                .clipShape(.rect(cornerRadius: 30, style: .continuous))
        }
        .contentShape(.rect(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(counts: counts))
        .accessibilityHint(isLink ? "Shows how the index is made up" : "")
    }

    @ViewBuilder private func chips(_ levels: [Level], _ counts: [Level: Int]) -> some View {
        ForEach(levels, id: \.self) { level in
            GlassCountChip(level: level, count: counts[level, default: 0])
        }
    }

    private func accessibilityText(counts: [Level: Int]) -> String {
        let world = board.status.world
        let score = world.score.map { "\($0) out of 100" } ?? "not available"
        return "World State \(score), \(world.bandKind.rawValue). \(counts[.alert, default: 0]) on Alert, \(counts[.watch, default: 0]) on Watch, \(counts[.normal, default: 0]) Normal. \(board.status.headline ?? "")"
    }
}

// MARK: - Pinned

private struct PinnedSection: View {
    let board: Board

    @Environment(PinStore.self) private var pins
    @State private var showsEditor = false

    var body: some View {
        let pinned = pins.ids.compactMap { board.signal($0) }
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Pinned") {
                Button(pinned.isEmpty ? "Add" : "Edit") { showsEditor = true }
            }
            if pinned.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    IconBadge(systemImage: "pin.fill", color: .blue)
                    Text("Pin the signals you follow")
                        .font(.headline)
                    Text("They appear here as tiles, with their latest level and a chart of recent checks.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Choose Signals") { showsEditor = true }
                        .buttonStyle(.glass)
                }
                .tile(tint: .blue)
            } else {
                SignalTileGrid(signals: pinned)
            }
        }
        .sheet(isPresented: $showsEditor) { PinEditorView() }
    }
}

// MARK: - Highlights

/// How many signals were at each level at the end of each day.
private struct AttentionHighlight: View {
    let board: Board
    @Environment(BoardStore.self) private var store

    var body: some View {
        let data = board.dailyLevelMix(days: 7, now: store.now)
        let byDay = Dictionary(grouping: data, by: \.day).sorted { $0.key < $1.key }
        let alertsNow = board.counts(at: store.now)[.alert, default: 0]
        VStack(alignment: .leading, spacing: 12) {
            TileHeader(title: "Attention by Day", systemImage: "chart.bar.fill", hue: Level.alert.hue)
            Text(sentence(byDay: byDay, alertsNow: alertsNow))
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if byDay.count >= 2 {
                LevelMixColumns(data: data)
                    .frame(height: 150)
            }
            LevelLegend(counts: board.counts(at: store.now))
        }
        .tile(tint: Level.alert.color)
    }

    private func sentence(byDay: [(key: Date, value: [DayLevelCount])], alertsNow: Int) -> String {
        guard let first = byDay.first, byDay.count >= 2 else {
            return "\(alertsNow) signals are on Alert."
        }
        let then = first.value.first { $0.level == .alert }?.count ?? 0
        let day = first.key.formatted(.dateTime.weekday(.wide))
        if alertsNow > then { return "\(alertsNow) signals are on Alert, up from \(then) on \(day)." }
        if alertsNow < then { return "\(alertsNow) signals are on Alert, down from \(then) on \(day)." }
        return "\(alertsNow) signals are on Alert, the same as on \(day)."
    }
}

/// Level changes per day: up to more attention, or eased.
private struct MovesHighlight: View {
    let board: Board
    @Environment(BoardStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let data = board.dailyMoves(days: 7, now: store.now)
        let up = data.map(\.up).reduce(0, +)
        let down = data.map(\.down).reduce(0, +)
        Button {
            router.tab = .changes
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                TileHeader(title: "Level Changes", systemImage: "arrow.up.arrow.down",
                           hue: Hue(fill: MovesColumns.upColor, text: Color.primary), showsChevron: true)
                Text(sentence(up: up, down: down, since: data.first?.day))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !data.isEmpty {
                    MovesColumns(data: data)
                        .frame(height: 130)
                }
                MovesLegend(up: up, down: down)
            }
            .tile(tint: MovesColumns.upColor)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows every change")
    }

    private func sentence(up: Int, down: Int, since: Date?) -> String {
        let day = since?.formatted(.dateTime.weekday(.wide)) ?? "the first check"
        if up + down == 0 { return "No signal has changed level since \(day)." }
        return "\(up) moved up and \(down) eased since \(day)."
    }
}

/// The domains under most strain, in their colours.
private struct DomainsHighlight: View {
    let board: Board

    var body: some View {
        let items = Array(board.domainScores.prefix(5))
        VStack(alignment: .leading, spacing: 12) {
            TileHeader(title: "Most Strained Domains", systemImage: "square.grid.2x2.fill",
                       hue: DomainStyle.hue(for: items.first?.domain.id ?? ""))
            if let top = items.first {
                Text("\(top.domain.name) is under most strain, at \(top.score) out of 100.")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                DomainBars(items: items)
            } else {
                Text("Domain scores aren't available for this run.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .tile(tint: DomainStyle.color(for: items.first?.domain.id ?? ""))
    }
}

/// Status changes in the last 24 hours.
private struct ChangedSection: View {
    let board: Board
    @Environment(BoardStore.self) private var store

    var body: some View {
        let changes = board.recentChanges(hours: 24, at: store.now)
        VStack(alignment: .leading, spacing: 10) {
            TileHeader(title: "Changed in the Last 24 Hours", systemImage: "clock.arrow.circlepath",
                       hue: Hue(fill: .blue, text: .primary))
            if changes.isEmpty {
                Text("No signal has changed level in the last 24 hours.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(changes.prefix(5).enumerated()), id: \.element.key) { index, change in
                        NavigationLink(value: Route.signal(change.id)) {
                            ChangeRow(change: change)
                                .padding(.vertical, 8)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if index < min(changes.count, 5) - 1 { Divider() }
                    }
                }
            }
        }
        .tile(tint: .blue)
    }
}

// MARK: - On Alert

private struct AlertNowSection: View {
    let board: Board
    @Environment(BoardStore.self) private var store

    var body: some View {
        let alerts = board.signals(withLevel: .alert, at: store.now)
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("On Alert") {
                    NavigationLink("Show All", value: Route.level(.alert))
                }
                VStack(spacing: 0) {
                    ForEach(Array(alerts.prefix(6).enumerated()), id: \.element.id) { index, signal in
                        NavigationLink(value: Route.signal(signal.id)) {
                            SignalRow(signal: signal, showsDomain: true, showsSummary: false)
                                .padding(.vertical, 8)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if index < min(alerts.count, 6) - 1 { Divider() }
                    }
                    if alerts.count > 6 {
                        Divider()
                        NavigationLink(value: Route.level(.alert)) {
                            HStack {
                                Text("\(alerts.count - 6) more on Alert")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .font(.subheadline)
                            .padding(.vertical, 10)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .tile(tint: Level.alert.color, padding: 14)
            }
        }
    }
}

// MARK: - Situations

private struct SituationsSection: View {
    let board: Board

    var body: some View {
        if !board.situations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Situations") {
                    NavigationLink("Show All", value: Route.situations)
                }
                ForEach(board.situations.sorted { $0.status.rank < $1.status.rank }.prefix(4)) { situation in
                    NavigationLink(value: Route.situation(situation.id)) {
                        SituationCard(situation: situation)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A situation as a tile: its level, name, summary, and its signals' levels as
/// one bar.
struct SituationCard: View {
    let situation: Situation
    @Environment(BoardStore.self) private var store

    var body: some View {
        let members = store.board.map { $0.signals(inSituation: situation, at: store.now) } ?? []
        let counts = store.board?.counts(in: members, at: store.now) ?? [:]
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                StatusLabel(situation.status, font: .subheadline.weight(.semibold))
                if let trend = situation.trend, trend != .unknown {
                    Label(trend.label, systemImage: trend.symbol)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            Text(situation.name)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if let summary = situation.summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !members.isEmpty {
                LevelBar(counts: counts, height: 7)
                    .padding(.top, 2)
            }
            Text("^[\(situation.signals.count) signal](inflect: true)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .tile(tint: situation.status.color)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Footer

/// Disclaimer, AI disclosure and a link to the method, as on the website.
struct AboutFooter: View {
    let board: Board

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(board.status.disclaimer ?? "Attention levels describe current conditions. They are not a forecast, and not financial, medical, legal or safety advice.")
            Text("Statuses are assessed by an AI model (Anthropic's Claude) against published rubrics, four times a day. \(board.basisCount(.judged)) of \(board.signals.count) are AI judgements; the rest follow measured data or published figures.")
            Link("How Canary Works", destination: AppConstants.methodologyURL)
                .font(.footnote.weight(.semibold))
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .opensLinksInApp()
    }
}
