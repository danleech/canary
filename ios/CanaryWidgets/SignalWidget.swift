import AppIntents
import SwiftUI
import WidgetKit

/// One chosen signal, Stocks-style. Part of Canary+.
struct SignalWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKinds.signal, intent: SelectSignalIntent.self, provider: SignalProvider()) { entry in
            SignalWidgetView(entry: entry)
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

struct SignalEntry: TimelineEntry {
    let date: Date
    let signal: Signal?
    let history: [HistoryPoint]
    let isPlus: Bool
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

struct SignalWidgetView: View {
    let entry: SignalEntry
    @Environment(\.widgetFamily) private var family

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

#Preview(as: .systemSmall) {
    SignalWidget()
} timeline: {
    SignalEntry(date: .now, signal: SampleBoard.board.signal("oil"),
                history: SampleBoard.board.history(for: "oil"), isPlus: true)
}
