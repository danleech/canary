import SwiftUI
import WidgetKit

// Widget entries and views, shared so the app can render them too (the debug
// widget gallery). Each view takes its family explicitly; the widget extension
// passes the one WidgetKit gives it through `WidgetFamilyReader`.

/// Reads the widget family from the environment and hands it to its content.
struct WidgetFamilyReader<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @ViewBuilder let content: (WidgetFamily) -> Content

    var body: some View { content(family) }
}

struct WorldEntry: TimelineEntry {
    let date: Date
    let board: Board?
}

struct WorldStateWidgetView: View {
    let entry: WorldEntry
    var family: WidgetFamily = .systemSmall

    var body: some View {
        if let board = entry.board {
            switch family {
            case .accessoryCircular: circular(board)
            case .accessoryRectangular: rectangular(board)
            case .accessoryInline: inline(board)
            case .systemMedium: medium(board)
            default: small(board)
            }
        } else {
            NoBoardView()
        }
    }

    private func score(_ board: Board) -> String { board.status.world.score.map(String.init) ?? "–" }

    private func small(_ board: Board) -> some View {
        let counts = board.counts(at: entry.date)
        return VStack(alignment: .leading, spacing: 4) {
            WidgetCaption(text: "World State", systemImage: "globe")
            Spacer(minLength: 0)
            Text(score(board))
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .widgetAccentable()
            Text(board.status.world.bandKind.rawValue)
                .font(.headline)
            WorldGaugeBar(score: board.status.world.score, height: 5)
                .padding(.vertical, 2)
            HStack(spacing: 8) {
                countLabel(.alert, counts)
                countLabel(.watch, counts)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ board: Board) -> some View {
        let alerts = board.signals(withLevel: .alert, at: entry.date)
        return HStack(alignment: .top, spacing: 16) {
            small(board)
                .overlay(alignment: .topTrailing) {
                    ScoreRing(score: board.status.world.score, band: board.status.world.bandKind, lineWidth: 7)
                        .frame(width: 44, height: 44)
                        .widgetAccentable()
                }
            VStack(alignment: .leading, spacing: 6) {
                WidgetCaption(text: "On Alert", systemImage: Level.alert.symbol)
                ForEach(alerts.prefix(4)) { signal in
                    HStack(spacing: 6) {
                        StatusGlyph(.alert, font: .caption)
                        Text(signal.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                }
                if alerts.count > 4 {
                    Text("\(alerts.count - 4) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func circular(_ board: Board) -> some View {
        Gauge(value: Double(board.status.world.score ?? 0), in: 0...100) {
            Image(systemName: "globe")
        } currentValueLabel: {
            Text(score(board))
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
        .accessibilityLabel("World State \(score(board)), \(board.status.world.bandKind.rawValue)")
    }

    private func rectangular(_ board: Board) -> some View {
        let counts = board.counts(at: entry.date)
        return VStack(alignment: .leading, spacing: 1) {
            Text("World State \(score(board))")
                .font(.headline)
                .widgetAccentable()
            Text(board.status.world.bandKind.rawValue)
                .font(.subheadline)
            Text("\(counts[.alert, default: 0]) Alert · \(counts[.watch, default: 0]) Watch")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ board: Board) -> some View {
        Label("World State \(score(board)) · \(board.status.world.bandKind.rawValue)", systemImage: "globe")
    }

    private func countLabel(_ level: Level, _ counts: [Level: Int]) -> some View {
        HStack(spacing: 3) {
            StatusGlyph(level, font: .caption2)
            Text("\(counts[level, default: 0])")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(counts[level, default: 0]) \(level.label)")
    }
}

struct SignalEntry: TimelineEntry {
    let date: Date
    let signal: Signal?
    let history: [HistoryPoint]
    let isPlus: Bool
}

struct SignalWidgetView: View {
    let entry: SignalEntry
    var family: WidgetFamily = .systemSmall

    var body: some View {
        if !entry.isPlus {
            if family == .systemSmall { PlusRequiredView() } else { Image(systemName: "bird.fill") }
        } else if let signal = entry.signal {
            content(signal)
                .widgetURL(DeepLink.signal(signal.id).url)
        } else {
            NoBoardView()
        }
    }

    @ViewBuilder private func content(_ signal: Signal) -> some View {
        let level = signal.level(at: entry.date)
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: level.symbol)
                        .font(.title3)
                        .widgetAccentable()
                    Text(level.label)
                        .font(.system(size: 10, weight: .semibold))
                        .minimumScaleFactor(0.7)
                }
            }
            .accessibilityLabel(signal.accessibilitySummary(at: entry.date))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(signal.name)
                    .font(.headline)
                    .lineLimit(1)
                Label(level.label, systemImage: level.symbol)
                    .font(.subheadline.weight(.semibold))
                    .widgetAccentable()
                if let value = signal.value {
                    Text(value)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                WidgetCaption(text: LocalizedStringKey(signal.domainName ?? signal.domain.capitalized),
                              systemImage: DomainStyle.symbol(for: signal.domain))
                Text(signal.name)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Sparkline(points: entry.history, level: level)
                    .frame(height: 26)
                StatusLabel(level, font: .title3.weight(.bold))
                    .widgetAccentable()
                if let value = signal.value {
                    Text(value)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(signal.accessibilitySummary(at: entry.date))
        }
    }
}

struct PinnedEntry: TimelineEntry {
    let date: Date
    let board: Board?
    let pinnedIDs: [String]
    let isPlus: Bool
}

struct PinnedWidgetView: View {
    let entry: PinnedEntry
    var family: WidgetFamily = .systemSmall

    var body: some View {
        if !entry.isPlus {
            PlusRequiredView()
        } else if let board = entry.board {
            let pinned = entry.pinnedIDs.compactMap { board.signal($0) }
            let showsAlerts = pinned.isEmpty
            let rows = showsAlerts ? board.signals(withLevel: .alert, at: entry.date) : pinned
            let limit = family == .systemLarge ? 7 : 3
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    WidgetCaption(text: showsAlerts ? "On Alert" : "Pinned", systemImage: showsAlerts ? Level.alert.symbol : "pin.fill")
                    Spacer()
                    Text(board.status.asOf, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 6)
                ForEach(Array(rows.prefix(limit).enumerated()), id: \.element.id) { index, signal in
                    Link(destination: DeepLink.signal(signal.id).url) {
                        row(signal, board: board)
                    }
                    if index < min(rows.count, limit) - 1 { Divider() }
                }
                Spacer(minLength: 0)
            }
        } else {
            NoBoardView()
        }
    }

    private func row(_ signal: Signal, board: Board) -> some View {
        let level = signal.level(at: entry.date)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(signal.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(signal.value ?? signal.domainName ?? "")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Sparkline(points: board.history(for: signal.id), level: level)
                .frame(width: 48, height: 22)
            StatusPill(level, compact: true)
                .widgetAccentable()
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(signal.accessibilitySummary(at: entry.date))
    }
}

// MARK: - Shared widget views

/// Small uppercase caption used at the top of widgets.
struct WidgetCaption: View {
    let text: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// Shown in Canary+ widgets when the subscription isn't active.
struct PlusRequiredView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "bird.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            Text("Canary+")
                .font(.headline)
            Text("Open Canary to subscribe and show signals here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "\(AppConstants.urlScheme)://world"))
    }
}

/// Shown when no board could be loaded at all.
struct NoBoardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
            Text("Open Canary to load the board.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
