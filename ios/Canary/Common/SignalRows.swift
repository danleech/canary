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
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

/// Stocks-style row for pinned signals: name and domain, sparkline, level pill and value.
struct PinnedRow: View {
    let signal: Signal

    @Environment(BoardStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let level = signal.level(at: store.now)
        let history = store.board?.history(for: signal.id) ?? []
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    title
                    StatusPill(level)
                    valueText
                }
            } else {
                HStack(spacing: 12) {
                    title
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Sparkline(points: history, level: level)
                        .frame(width: 64, height: 30)
                    VStack(alignment: .trailing, spacing: 4) {
                        StatusPill(level)
                        valueText
                    }
                    .frame(minWidth: 84, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(signal.accessibilitySummary(at: store.now))
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Wrap rather than truncate: names and domains stay whole on narrow iPhones.
            Text(signal.name)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(signal.domainName ?? signal.domain.capitalized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var valueText: some View {
        if let value = signal.value {
            Text(value)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
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
