import SwiftUI

/// The standard list row: level glyph, name, value and summary, trend arrow.
struct SignalRow: View {
    let signal: Signal
    var showsDomain = false
    var showsSummary = true

    @Environment(BoardStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let level = signal.level(at: store.now)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            StatusGlyph(level, font: .body)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(signal.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if !typeSize.isAccessibilitySize { trend }
                }
                if showsDomain {
                    Text(signal.domainName ?? signal.domain.capitalized)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DomainStyle.hue(for: signal.domain).text)
                }
                if let value = signal.value {
                    Text(value)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if showsSummary, let summary = signal.summary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if typeSize.isAccessibilitySize { trend }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(signal.accessibilitySummary(at: store.now))
        .accessibilityHint(signal.summary ?? "")
    }

    @ViewBuilder private var trend: some View {
        if let trend = signal.trend, trend != .unknown {
            Image(systemName: trend.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel(trend.label)
        }
    }
}

/// A widget-sized tile for one signal, as Health shows a pinned data type: the
/// domain in its colour, the name, a small chart of recent checks, the level
/// and the key value. Text wraps rather than truncating.
struct SignalTile: View {
    let signal: Signal
    var showsDomain = true

    @Environment(BoardStore.self) private var store
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 196

    var body: some View {
        let level = signal.level(at: store.now)
        let hue = DomainStyle.hue(for: signal.domain)
        let history = store.board?.history(for: signal.id) ?? []
        VStack(alignment: .leading, spacing: 8) {
            if showsDomain {
                Label {
                    Text(DomainStyle.shortName(for: signal.domain, fallback: signal.domainName ?? signal.domain))
                } icon: {
                    Image(systemName: DomainStyle.symbol(for: signal.domain))
                        .foregroundStyle(hue.fill)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(hue.text)
            }
            Text(signal.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            TileChart(history: history, level: level, tint: hue.fill)
                .frame(height: chartHeight)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                StatusGlyph(level, font: .callout)
                Text(level.label)
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(level.textColor)
                Spacer(minLength: 0)
                if let trend = signal.trend, trend != .unknown {
                    Image(systemName: trend.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            if let value = signal.value {
                Text(value)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
        .tile(tint: hue.fill, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(signal.accessibilitySummary(at: store.now))
        .accessibilityHint(signal.summary ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

/// Signal tiles in a grid that fits two to a row on iPhone and more on wider
/// displays, each linking to the signal.
struct SignalTileGrid: View {
    let signals: [Signal]
    var showsDomain = true

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let minimum: CGFloat = typeSize.isAccessibilitySize ? 320 : 158
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 12, alignment: .top)], spacing: 12) {
            ForEach(signals) { signal in
                NavigationLink(value: Route.signal(signal.id)) {
                    SignalTile(signal: signal, showsDomain: showsDomain)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A status change: from → to, name, reason and time.
struct ChangeRow: View {
    let change: StatusChange
    var showsDay = false

    @Environment(BoardStore.self) private var store

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            StatusGlyph(change.to)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(change.name)
                        .font(.body.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(showsDay ? CanaryFormat.when(change.t, now: store.now)
                                  : change.t.formatted(date: .omitted, time: .shortened))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Text(change.from.label)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(change.to.label)
                }
                .font(.subheadline.weight(.medium))
                if let reason = change.reason {
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(change.name) changed from \(change.from.label) to \(change.to.label), \(CanaryFormat.when(change.t, now: store.now)). \(change.reason ?? "")")
    }
}
