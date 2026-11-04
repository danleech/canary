import AppIntents
import SwiftUI
import WidgetKit

/// One chosen signal, Stocks-style. Part of Canary+.
struct SignalWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKinds.signal, intent: SelectSignalIntent.self, provider: SignalProvider()) { entry in
            WidgetFamilyReader { family in SignalWidgetView(entry: entry, family: family) }
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Signal")
        .description("One signal's level, trend and key value. Requires Canary+.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct SelectSignalIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Signal"
    static let description = IntentDescription("Choose the signal to show.")

    @Parameter(title: "Signal")
    var signal: SignalEntity?
}

struct SignalProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SignalEntry {
        let board = SampleBoard.board
        return SignalEntry(date: .now, signal: board.signal("oil"), history: board.history(for: "oil"), isPlus: true)
    }

    func snapshot(for configuration: SelectSignalIntent, in context: Context) async -> SignalEntry {
        if context.isPreview { return placeholder(in: context) }
        return await entry(for: configuration, board: WidgetBoard.load())
    }

    func timeline(for configuration: SelectSignalIntent, in context: Context) async -> Timeline<SignalEntry> {
        let board = await WidgetBoard.load()
        return Timeline(entries: [entry(for: configuration, board: board)],
                        policy: .after(WidgetBoard.nextReload(for: board)))
    }

    private func entry(for configuration: SelectSignalIntent, board: Board?) -> SignalEntry {
        // Default: the first pinned signal, otherwise the first on Alert.
        let id = configuration.signal?.id
            ?? SharedSettings.pinnedIDs.first
            ?? board?.signals(withLevel: .alert).first?.id
        let signal = id.flatMap { board?.signal($0) }
        return SignalEntry(date: .now, signal: signal, history: id.map { board?.history(for: $0) ?? [] } ?? [],
                           isPlus: SharedSettings.isPlus)
    }
}

#Preview(as: .systemSmall) {
    SignalWidget()
} timeline: {
    SignalEntry(date: .now, signal: SampleBoard.board.signal("oil"),
                history: SampleBoard.board.history(for: "oil"), isPlus: true)
}
