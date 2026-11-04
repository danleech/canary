import Accessibility
import Charts
import SwiftUI

/// One signal in full, like a Health data type or a Stocks quote: its level,
/// a chart of recent checks, why it's at this level, what it means for you,
/// how the level was set, the thresholds, and sources.
struct SignalDetailView: View {
    let signalID: String

    @Environment(BoardStore.self) private var store
    @Environment(PinStore.self) private var pins
    @Environment(PlusStore.self) private var plus
    @State private var showsPaywall = false

    var body: some View {
        if let board = store.board, let signal = board.signal(signalID) {
            let hue = DomainStyle.hue(for: signal.domain)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SignalHeader(signal: signal)
                    AdaptiveColumns {
                        SignalChartCard(signal: signal, history: board.history(for: signal.id))
                        if signal.withholdsFigures {
                            WithheldFiguresCard(url: signal.url)
                        }
                        LevelTimelineCard(spans: board.levelSpans(for: signal.id, now: store.now))
                        TextCard(title: "Why It's at This Level", systemImage: "text.alignleft", text: signal.state)
                        TextCard(title: "What This Means for You", systemImage: "person", text: signal.forYou)
                        BasisCard(signal: signal)
                    } trailing: {
                        if let entry = board.entry(signal.id) {
                            ThresholdsCard(rubric: entry.rubric, current: signal.level(at: store.now))
                            TextCard(title: "Why It Matters", systemImage: "info.circle", text: entry.why)
                            TextCard(title: "What Drives It", systemImage: "arrow.triangle.branch", text: entry.drivers)
                        }
                        SituationLinks(situations: board.situations(for: signal))
                        SourcesCard(sources: signal.sources ?? [])
                    }
                    DetailFooter(signal: signal)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .debugScrollable()
            .environment(\.pageHue, hue)
            .background { WashedBackground(tint: hue.fill) }
            .scrollRevealedTitle(signal.name)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { pinButton(signal) }
                if let url = signal.url {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url, subject: Text(signal.name),
                                  message: Text("\(signal.name): \(signal.level(at: store.now).label). \(signal.summary ?? "")")) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $showsPaywall) { CanaryPlusView(reason: .pins) }
            .opensLinksInApp()
            .userActivity("com.danleech.canary.signal") { activity in
                activity.title = signal.name
                activity.webpageURL = signal.url
                activity.isEligibleForSearch = true
                activity.isEligibleForHandoff = true
            }
        } else {
            ContentUnavailableView("Signal Not Found", systemImage: "questionmark.circle",
                                   description: Text("It may have been renamed or removed from the catalogue."))
        }
    }

    private func pinButton(_ signal: Signal) -> some View {
        let pinned = pins.isPinned(signal.id)
        return Button {
            if pinned {
                pins.unpin(signal.id)
            } else if pins.canPin(isPlus: plus.isPlus) {
                pins.pin(signal.id)
            } else {
                showsPaywall = true
            }
        } label: {
            Label(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.fill" : "pin")
        }
        .sensoryFeedback(.selection, trigger: pinned)
    }
}

// MARK: - Header

private struct SignalHeader: View {
    let signal: Signal
    @Environment(BoardStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let level = signal.level(at: store.now)
        // Level and trend side by side, stacked at accessibility text sizes.
        let levelLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconBadge(systemImage: DomainStyle.symbol(for: signal.domain),
                          color: DomainStyle.color(for: signal.domain), size: 26)
                Text(signal.domainName ?? signal.domain.capitalized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DomainStyle.hue(for: signal.domain).text)
            }
            Text(signal.name)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
            levelLayout {
                StatusLabel(level, font: .title2.weight(.bold))
                if let trend = signal.trend, trend != .unknown {
                    Label(trend.label, systemImage: trend.symbol)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            if let value = signal.value {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            if let summary = signal.summary {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let changed = signal.changedAt, level != .stale {
                Text("\(level.label) for \(CanaryFormat.duration(since: changed, now: store.now))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if level == .stale {
                Label("Not verified since \(signal.checkedAt.map { CanaryFormat.when($0, now: store.now) } ?? "the last run"). Its last assessed level was \(signal.status.label).",
                      systemImage: "clock.badge.questionmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Chart

/// The key value at each check, as Health charts a measurement: a smoothed
/// line over a gradient in the domain's colour, dots in each check's level
/// colour, and a range to choose. Signals without a number show only their
/// level timeline (below).
private struct SignalChartCard: View {
    let signal: Signal
    let history: [HistoryPoint]

    enum Range: String, CaseIterable, Identifiable {
        case day = "D", week = "W", all = "All"
        var id: String { rawValue }
        var seconds: TimeInterval? {
            switch self {
            case .day: 86_400
            case .week: 7 * 86_400
            case .all: nil
            }
        }
    }

    @Environment(BoardStore.self) private var store
    @State private var range: Range = .all
    @State private var touch: Date?
    @State private var pinned: Date?

    var body: some View {
        let hue = DomainStyle.hue(for: signal.domain)
        let series = history.filter { $0.value != nil }
        let shown = range.seconds.map { window in
            series.filter { $0.date >= store.now.addingTimeInterval(-window) }
        } ?? series
        let selected = (touch ?? pinned).flatMap { date in
            shown.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        if series.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                ModuleHeader("Key Value at Each Check", systemImage: "chart.xyaxis.line")
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: range) {
                    touch = nil
                    pinned = nil
                }
                if let selected, let value = selected.value {
                    // Health keeps the touched check in the header until it's cleared.
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("SELECTED")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(value.formatted(.number.precision(.fractionLength(0...2))))
                                .font(.title2.weight(.bold))
                                .fontDesign(.rounded)
                                .monospacedDigit()
                            Text("\(selected.level.label) · \(selected.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))")
                                .font(.footnote)
                                .foregroundStyle(selected.level.textColor)
                        }
                        Spacer()
                        Button("Clear Selection", systemImage: "xmark.circle.fill") {
                            touch = nil
                            pinned = nil
                        }
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .contain)
                } else if let latest = series.last?.value {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("LATEST")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(signal.value ?? latest.formatted(.number.precision(.fractionLength(0...2))))
                            .font(.title2.weight(.bold))
                            .fontDesign(.rounded)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if shown.count >= 2 {
                    ValueChart(history: shown, tint: hue.fill, selection: $touch, highlighted: pinned)
                        .frame(height: 210)
                        .accessibilityChartDescriptor(SeriesDescriptor(name: signal.name, points: shown))
                        .accessibilityIdentifier("valueChart")
                        .onChange(of: touch) { _, date in
                            if let date { pinned = date }
                        }
                } else {
                    Text("Only one check in this range. Choose a longer one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                Text("^[\(series.count) check](inflect: true) since \(series[0].date.formatted(date: .abbreviated, time: .omitted)). Touch the chart to see a check.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .tile(tint: hue.fill)
        }
    }
}

/// Explains why a market signal shows no figures in the app.
private struct WithheldFiguresCard: View {
    let url: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModuleHeader("Figures Not Shown", systemImage: "lock.doc")
            Text("This level is set from market data whose licence doesn't allow Canary to republish the figures in the app. The level, its history and the assessment are shown; the numbers are on the free website.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let url {
                Link("See the Figures on the Web", destination: url)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .tile()
    }
}

/// The level over time, as Health shows sleep stages: one row per level.
private struct LevelTimelineCard: View {
    let spans: [LevelSpan]

    var body: some View {
        if !spans.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ModuleHeader("Level Over Time", systemImage: "chart.bar.xaxis")
                if let current = spans.last {
                    Text("\(current.level.label) since \(current.start.formatted(.dateTime.day().month(.wide).hour().minute()))")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LevelTimeline(spans: spans)
                    .frame(height: 120)
            }
            .tile(tint: spans.last?.level.color)
        }
    }
}

/// Lets VoiceOver users explore the chart as audio graphs.
private struct SeriesDescriptor: AXChartDescriptorRepresentable {
    let name: String
    let points: [HistoryPoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let values = points.compactMap(\.value)
        let x = AXNumericDataAxisDescriptor(
            title: "Time",
            range: (points.first?.date.timeIntervalSince1970 ?? 0)...(points.last?.date.timeIntervalSince1970 ?? 1),
            gridlinePositions: []
        ) { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .shortened) }
        let y = AXNumericDataAxisDescriptor(
            title: "Value",
            range: (values.min() ?? 0)...(values.max() ?? 1),
            gridlinePositions: []
        ) { $0.formatted(.number.precision(.fractionLength(0...2))) }
        let series = AXDataSeriesDescriptor(
            name: name,
            isContinuous: true,
            dataPoints: points.compactMap { point in
                point.value.map { AXDataPoint(x: point.date.timeIntervalSince1970, y: $0, label: point.level.label) }
            }
        )
        return AXChartDescriptor(title: name, summary: nil, xAxis: x, yAxis: y, additionalAxes: [], series: [series])
    }
}

// MARK: - Text sections

struct TextCard: View {
    let title: LocalizedStringKey
    let systemImage: String
    let text: String?

    var body: some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ModuleHeader(title, systemImage: systemImage)
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .tile()
        }
    }
}

/// How the level was set: measured, published or AI judgement, with the rule.
private struct BasisCard: View {
    let signal: Signal

    var body: some View {
        let basis = signal.basis ?? .unknown
        VStack(alignment: .leading, spacing: 10) {
            ModuleHeader("How This Level Was Set", systemImage: "checkmark.seal")
            HStack(spacing: 10) {
                IconBadge(systemImage: basis.symbol, color: basis.hue.fill, size: 30)
                Text(basis.label)
                    .font(.headline)
                    .foregroundStyle(basis.hue.text)
            }
            Text(basis.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let rule = signal.rubricHit {
                LabeledContent("Rule met") {
                    Text(rule).multilineTextAlignment(.trailing)
                }
                .font(.subheadline)
            }
            if basis == .published, let publisher = signal.basisBy {
                LabeledContent("Published by") {
                    Text(publisher).multilineTextAlignment(.trailing)
                }
                .font(.subheadline)
            } else if basis == .measured, let detail = signal.basisDetail {
                LabeledContent("Inputs") {
                    Text(detail).monospacedDigit().multilineTextAlignment(.trailing)
                }
                .font(.subheadline)
            }
        }
        .tile()
    }
}

/// The rubric for each level, with the current one marked.
private struct ThresholdsCard: View {
    let rubric: Rubric?
    let current: Level

    var body: some View {
        if let rubric {
            VStack(alignment: .leading, spacing: 12) {
                ModuleHeader("Thresholds", systemImage: "slider.horizontal.3")
                LevelScale(current: current)
                ForEach([Level.alert, .watch, .normal], id: \.self) { level in
                    if let text = rubric.text(for: level) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            StatusGlyph(level)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(level.label).font(.subheadline.weight(.semibold))
                                    if level == current {
                                        Text("Now")
                                            .font(.caption2.weight(.bold))
                                            .textCase(.uppercase)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(.quaternary, in: .capsule)
                                    }
                                }
                                Text(text)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(level.label)\(level == current ? ", current level" : ""): \(text)")
                    }
                }
                Text("A level changes only when evidence clearly crosses a threshold, and by at most one step per run unless an official trigger fires.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .tile()
        }
    }
}

/// Normal, Watch and Alert as one scale with the current level marked, as
/// Health shows a measurement against its ranges.
private struct LevelScale: View {
    let current: Level

    var body: some View {
        HStack(spacing: 4) {
            ForEach([Level.normal, .watch, .alert], id: \.self) { level in
                VStack(spacing: 5) {
                    Capsule()
                        .fill(level.color.gradient)
                        .opacity(level == current ? 1 : 0.28)
                        .frame(height: level == current ? 10 : 8)
                    Text(level.label)
                        .font(.caption.weight(level == current ? .bold : .regular))
                        .foregroundStyle(level == current ? level.textColor : Color.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current level: \(current.label)")
    }
}

private struct SituationLinks: View {
    let situations: [Situation]

    var body: some View {
        if !situations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ModuleHeader("Part Of", systemImage: "point.3.connected.trianglepath.dotted")
                ForEach(situations) { situation in
                    NavigationLink(value: Route.situation(situation.id)) {
                        HStack(spacing: 10) {
                            StatusGlyph(situation.status)
                            Text(situation.name)
                                .font(.body)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(situation.name), \(situation.status.label)")
                }
            }
            .tile()
        }
    }
}

private struct SourcesCard: View {
    let sources: [Source]

    var body: some View {
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ModuleHeader("Sources", systemImage: "link")
                ForEach(sources) { source in
                    Link(destination: source.url) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.title)
                                    .font(.subheadline.weight(.medium))
                                    .multilineTextAlignment(.leading)
                                Text([source.host, source.date].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .tile()
        }
    }
}

private struct DetailFooter: View {
    let signal: Signal
    @Environment(BoardStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let checked = signal.checkedAt {
                Text("Checked \(CanaryFormat.when(checked, now: store.now))")
            }
            if let changed = signal.changedAt {
                Text("Level last changed \(CanaryFormat.when(changed, now: store.now))")
            }
            if let url = signal.url {
                Link("View on the Web", destination: url)
                    .fontWeight(.semibold)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}
