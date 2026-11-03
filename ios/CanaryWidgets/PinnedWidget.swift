import SwiftUI
import WidgetKit

/// The pinned list, like the Stocks watchlist widget. Part of Canary+.
/// With nothing pinned it shows what's on Alert.
struct PinnedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.pinned, provider: PinnedProvider()) { entry in
            PinnedWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Pinned Signals")
        .description("The signals you've pinned in Canary. Requires Canary+.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct PinnedEntry: TimelineEntry {
    let date: Date
    let board: Board?
    let pinnedIDs: [String]
    let isPlus: Bool
}

struct PinnedProvider: TimelineProvider {
    func placeholder(in context: Context) -> PinnedEntry {
        PinnedEntry(date: .now, board: SampleBoard.board, pinnedIDs: ["oil", "equity-stress", "ftse"], isPlus: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task {
            let board = await WidgetBoard.load()
            completion(PinnedEntry(date: .now, board: board, pinnedIDs: SharedSettings.pinnedIDs, isPlus: SharedSettings.isPlus))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedEntry>) -> Void) {
        Task {
            let board = await WidgetBoard.load()
            let entry = PinnedEntry(date: .now, board: board, pinnedIDs: SharedSettings.pinnedIDs, isPlus: SharedSettings.isPlus)
            completion(Timeline(entries: [entry], policy: .after(WidgetBoard.nextReload(for: board))))
        }
    }
}

struct PinnedWidgetView: View {
    let entry: PinnedEntry
    @Environment(\.widgetFamily) private var family

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

#Preview(as: .systemMedium) {
    PinnedWidget()
} timeline: {
    PinnedEntry(date: .now, board: SampleBoard.board, pinnedIDs: ["oil", "equity-stress", "ftse"], isPlus: true)
}
