import SwiftUI
import WidgetKit

/// World State on the Home Screen, Lock Screen and StandBy. Free for everyone.
struct WorldStateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.world, provider: WorldProvider()) { entry in
            WidgetFamilyReader { family in WorldStateWidgetView(entry: entry, family: family) }
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

#Preview(as: .systemSmall) {
    WorldStateWidget()
} timeline: {
    WorldEntry(date: .now, board: SampleBoard.board)
}
