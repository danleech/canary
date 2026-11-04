import SwiftUI
import WidgetKit

/// World State on the Home Screen, Lock Screen and StandBy. Free for everyone.
struct WorldStateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.world, provider: WorldProvider()) { entry in
            WorldStateWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    // The app's pastel mesh in the band's colours.
                    BandMeshBackground(band: entry.board?.status.world.bandKind ?? .unknown,
                                       base: Color(.systemBackground))
                }
                .widgetURL(DeepLink.world.url)
        }
        .configurationDisplayName("World State")
        .description("Canary's index of how much attention the world's risk signals deserve now.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WorldEntry: TimelineEntry {
    let date: Date
    let board: Board?
}

struct WorldProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorldEntry {
        WorldEntry(date: .now, board: SampleBoard.board)
    }

    func getSnapshot(in context: Context, completion: @escaping (WorldEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(WorldEntry(date: .now, board: await WidgetBoard.load() ?? SampleBoard.board)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorldEntry>) -> Void) {
        Task {
            let board = await WidgetBoard.load()
            let entry = WorldEntry(date: .now, board: board)
            completion(Timeline(entries: [entry], policy: .after(WidgetBoard.nextReload(for: board))))
        }
    }
}

struct WorldStateWidgetView: View {
    let entry: WorldEntry
    @Environment(\.widgetFamily) private var family

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

#Preview(as: .systemSmall) {
    WorldStateWidget()
} timeline: {
    WorldEntry(date: .now, board: SampleBoard.board)
}
