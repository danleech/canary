import SwiftUI

/// The first tab: World State, pinned signals, what's on Alert, what changed,
/// and the situations driving it. Modelled on Health's Summary.
struct SummaryView: View {
    @Environment(BoardStore.self) private var store
    @Environment(Router.self) private var router
    @State private var showsSettings = false

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.summaryPath) {
            ScrollView {
                if let board = store.board {
                    VStack(alignment: .leading, spacing: 20) {
                        if let message = store.errorMessage {
                            OfflineBanner(message: message)
                        }
                        AdaptiveColumns {
                            NavigationLink(value: Route.world) {
                                WorldStateCard(board: board)
                            }
                            .buttonStyle(.plain)
                            PinnedSection(board: board)
                            AlertNowSection(board: board)
                        } trailing: {
                            ChangedSection(board: board)
                            SituationsSection(board: board)
                        }
                        AboutFooter(board: board)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .background(Color(.systemGroupedBackground))
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
        .card(padding: 12)
    }
}

// MARK: - World State

/// Weather-style hero: the index, its band, a gradient gauge and the counts.
struct WorldStateCard: View {
    let board: Board
    var showsHeadline = true
    var isLink = true

    @Environment(BoardStore.self) private var store
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 64

    var body: some View {
        let world = board.status.world
        let band = world.bandKind
        let counts = board.counts(at: store.now)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ModuleHeader("World State", systemImage: "globe")
                Spacer()
                if isLink {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(world.score.map(String.init) ?? "–")
                    .font(.system(size: scoreSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                VStack(alignment: .leading, spacing: 0) {
                    Text(band.rawValue)
                        .font(.title2.weight(.semibold))
                    Text("out of 100")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            WorldGaugeBar(score: world.score)
            if showsHeadline, let headline = board.status.headline {
                Text(headline)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { countItems(counts) }
                VStack(alignment: .leading, spacing: 6) { countItems(counts) }
            }
            BoardFreshnessText()
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(counts: counts))
        .accessibilityHint(isLink ? "Shows how the index is made up" : "")
    }

    @ViewBuilder private func countItems(_ counts: [Level: Int]) -> some View {
        let levels: [Level] = counts[.stale, default: 0] > 0 ? [.alert, .watch, .normal, .stale] : [.alert, .watch, .normal]
        ForEach(levels, id: \.self) { level in
            HStack(spacing: 5) {
                StatusGlyph(level, font: .subheadline)
                Text("\(counts[level, default: 0]) \(level.label)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
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
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Pinned") {
                Button(pinned.isEmpty ? "Add" : "Edit") { showsEditor = true }
            }
            if pinned.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Pin the signals you follow", systemImage: "pin")
                        .font(.headline)
                    Text("They appear here with their latest level and a chart of recent checks, like a watchlist.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Choose Signals") { showsEditor = true }
                        .buttonStyle(.bordered)
                }
                .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(pinned.enumerated()), id: \.element.id) { index, signal in
                        NavigationLink(value: Route.signal(signal.id)) {
                            PinnedRow(signal: signal)
                        }
                        .buttonStyle(.plain)
                        if index < pinned.count - 1 { Divider() }
                    }
                }
                .card(padding: 14)
            }
        }
        .sheet(isPresented: $showsEditor) { PinEditorView() }
    }
}

// MARK: - On Alert

private struct AlertNowSection: View {
    let board: Board
    @Environment(BoardStore.self) private var store

    var body: some View {
        let alerts = board.signals(withLevel: .alert, at: store.now)
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("On Alert") {
                    NavigationLink("Show All", value: Route.level(.alert))
                }
                VStack(spacing: 0) {
                    ForEach(Array(alerts.prefix(5).enumerated()), id: \.element.id) { index, signal in
                        NavigationLink(value: Route.signal(signal.id)) {
                            SignalRow(signal: signal, showsDomain: true, showsSummary: false)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if index < min(alerts.count, 5) - 1 { Divider() }
                    }
                    if alerts.count > 5 {
                        Divider()
                        NavigationLink(value: Route.level(.alert)) {
                            HStack {
                                Text("\(alerts.count - 5) more on Alert")
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
                .card(padding: 14)
            }
        }
    }
}

// MARK: - Changed

private struct ChangedSection: View {
    let board: Board
    @Environment(BoardStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let changes = board.recentChanges(hours: 24, at: store.now)
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Changed in the Last 24 Hours") {
                Button("All") { router.tab = .changes }
            }
            if changes.isEmpty {
                Label("No signal has changed level in the last 24 hours.", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(changes.prefix(6).enumerated()), id: \.element.key) { index, change in
                        NavigationLink(value: Route.signal(change.id)) {
                            ChangeRow(change: change)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if index < min(changes.count, 6) - 1 { Divider() }
                    }
                }
                .card(padding: 14)
            }
        }
    }
}

// MARK: - Situations

private struct SituationsSection: View {
    let board: Board

    var body: some View {
        if !board.situations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Situations") {
                    NavigationLink("Show All", value: Route.situations)
                }
                ForEach(board.situations.prefix(4)) { situation in
                    NavigationLink(value: Route.situation(situation.id)) {
                        SituationCard(situation: situation)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A situation summary card: level, name, trend, summary and signal count.
struct SituationCard: View {
    let situation: Situation

    var body: some View {
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
            Text("^[\(situation.signals.count) signal](inflect: true)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
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
