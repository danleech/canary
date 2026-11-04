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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SignalHeader(signal: signal)
                    AdaptiveColumns {
                        SignalChartCard(signal: signal, history: board.history(for: signal.id))
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
            .background(Color(.systemGroupedBackground))
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
            Label(signal.domainName ?? signal.domain.capitalized, systemImage: DomainStyle.symbol(for: signal.domain))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
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

/// Swift Charts line of the key value, one point per check coloured by level.
/// Signals without a numeric series show the level at each check instead.
private struct SignalChartCard: View {
    let signal: Signal
    let history: [HistoryPoint]

    var body: some View {
        let series = history.filter { $0.value != nil }
        VStack(alignment: .leading, spacing: 12) {
            ModuleHeader(series.count >= 2 ? "Key Value at Each Check" : "Level at Each Check",
                         systemImage: "chart.xyaxis.line")
            if series.count >= 2 {
                Chart {
                    ForEach(Array(series.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Checked", point.date), y: .value("Value", point.value ?? 0))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Color.secondary.opacity(0.6))
                        PointMark(x: .value("Checked", point.date), y: .value("Value", point.value ?? 0))
                            .foregroundStyle(point.level.color)
                            .symbol { StatusGlyph(point.level, font: .system(size: 9)) }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 180)
                .accessibilityChartDescriptor(SeriesDescriptor(name: signal.name, points: series))
            } else if !history.isEmpty {
                StatusStrip(points: history, maxCount: 60)
                    .frame(height: 24)
            } else {
                Text("No checks recorded yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let first = history.first {
                Text("^[\(history.count) check](inflect: true) since \(first.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
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
            .card()
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
            Label(basis.label, systemImage: basis.symbol)
                .font(.headline)
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
        .card()
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
            .card()
        }
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
            .card()
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
            .card()
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
