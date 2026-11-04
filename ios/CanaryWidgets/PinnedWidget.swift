import SwiftUI
import WidgetKit

/// The pinned list, like the Stocks watchlist widget. Part of Canary+.
/// With nothing pinned it shows what's on Alert.
struct PinnedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.pinned, provider: PinnedProvider()) { entry in
            WidgetFamilyReader { family in PinnedWidgetView(entry: entry, family: family) }
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Pinned Signals")
        .description("The signals you've pinned in Canary. Requires Canary+.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
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

#Preview(as: .systemMedium) {
    PinnedWidget()
} timeline: {
    PinnedEntry(date: .now, board: SampleBoard.board, pinnedIDs: ["oil", "equity-stress", "ftse"], isPlus: true)
}
