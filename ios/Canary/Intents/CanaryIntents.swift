import AppIntents
import SwiftUI

// Siri and Shortcuts. Every intent answers from the public board; none needs
// Canary+ or sends anything about the person.

struct GetWorldStateIntent: AppIntent {
    static let title: LocalizedStringResource = "Get World State"
    static let description = IntentDescription("Tells you Canary's World State index and how many signals are on Alert and Watch.")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog & ShowsSnippetView {
        let board = try await IntentBoard.load()
        let world = board.status.world
        let counts = board.counts()
        let score = world.score ?? 0
        let dialog: IntentDialog = world.score == nil
            ? "Canary's World State isn't available right now."
            : "Canary's World State is \(score) out of 100, \(world.bandKind.rawValue). \(counts[.alert, default: 0]) signals are on Alert and \(counts[.watch, default: 0]) on Watch."
        return .result(value: score, dialog: dialog) {
            WorldStateSnippet(board: board)
        }
    }
}

struct CheckSignalIntent: AppIntent {
    static let title: LocalizedStringResource = "Check a Signal"
    static let description = IntentDescription("Tells you a signal's current level, trend and key value.")

    @Parameter(title: "Signal", requestValueDialog: "Which signal?")
    var signal: SignalEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$signal)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let board = try await IntentBoard.load()
        guard let current = board.signal(signal.id) else {
            throw $signal.needsValueError("That signal is no longer on the board. Which signal?")
        }
        let level = current.level()
        var sentence = "\(current.name) is on \(level.label)"
        if let trend = current.trend, trend != .unknown, level != .stale {
            sentence += " and \(trend.label.lowercased())"
        }
        sentence += "."
        if let summary = current.summary { sentence += " \(summary)." }
        return .result(value: level.label, dialog: IntentDialog(stringLiteral: sentence)) {
            SignalSnippet(signal: current, history: board.history(for: current.id))
        }
    }
}

struct ListAlertsIntent: AppIntent {
    static let title: LocalizedStringResource = "List Signals on Alert"
    static let description = IntentDescription("Lists the signals Canary currently has on Alert.")

    func perform() async throws -> some IntentResult & ReturnsValue<[SignalEntity]> & ProvidesDialog {
        let board = try await IntentBoard.load()
        let alerts = board.signals(withLevel: .alert)
        let names = alerts.prefix(5).map(\.name)
        let dialog: IntentDialog
        if alerts.isEmpty {
            dialog = "No signals are on Alert right now."
        } else {
            let more = alerts.count > 5 ? ", and \(alerts.count - 5) more" : ""
            dialog = IntentDialog(stringLiteral: "\(alerts.count) signals are on Alert: \(names.formatted(.list(type: .and)))\(more).")
        }
        return .result(value: alerts.map(SignalEntity.init), dialog: dialog)
    }
}

struct OpenSignalIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Signal"
    static let description = IntentDescription("Opens a signal in Canary.")
    static let openAppWhenRun = true

    @Parameter(title: "Signal")
    var signal: SignalEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$signal)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.open(.signal(signal.id))
        return .result()
    }
}

struct CanaryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetWorldStateIntent(),
            phrases: [
                "What's the world state in \(.applicationName)?",
                "Check the world state in \(.applicationName)",
                "\(.applicationName) world state",
            ],
            shortTitle: "World State",
            systemImageName: "gauge.with.dots.needle.50percent"
        )
        AppShortcut(
            intent: CheckSignalIntent(),
            phrases: [
                "Check \(\.$signal) in \(.applicationName)",
                "How is \(\.$signal) in \(.applicationName)?",
                "Check a signal in \(.applicationName)",
            ],
            shortTitle: "Check a Signal",
            systemImageName: "waveform.path.ecg"
        )
        AppShortcut(
            intent: ListAlertsIntent(),
            phrases: [
                "What's on alert in \(.applicationName)?",
                "List alerts in \(.applicationName)",
            ],
            shortTitle: "On Alert",
            systemImageName: "exclamationmark.octagon"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .yellow
}

// MARK: - Snippets

private struct WorldStateSnippet: View {
    let board: Board

    var body: some View {
        let world = board.status.world
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(world.score.map(String.init) ?? "–")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(world.bandKind.rawValue)
                    .font(.title3.weight(.semibold))
            }
            WorldGaugeBar(score: world.score)
            let counts = board.counts()
            HStack(spacing: 14) {
                ForEach([Level.alert, .watch, .normal], id: \.self) { level in
                    HStack(spacing: 4) {
                        StatusGlyph(level, font: .footnote)
                        Text("\(counts[level, default: 0]) \(level.label)")
                            .font(.footnote.weight(.medium))
                    }
                }
            }
        }
        .padding()
    }
}

private struct SignalSnippet: View {
    let signal: Signal
    let history: [HistoryPoint]

    var body: some View {
        let level = signal.level()
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                StatusLabel(level, font: .headline)
                if let value = signal.value {
                    Text(value)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Sparkline(points: history, level: level)
                .frame(width: 90, height: 36)
        }
        .padding()
    }
}
