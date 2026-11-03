import SwiftUI
import WidgetKit

@main
struct CanaryWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorldStateWidget()
        SignalWidget()
        PinnedWidget()
    }
}

// MARK: - Loading

/// Loads the board for a widget: the app's saved copy if recent, otherwise a
/// fresh fetch, otherwise whatever copy exists.
enum WidgetBoard {
    static func load() async -> Board? {
        let client = CanaryClient(timeout: 15)
        if let cached = client.cachedBoard(), Date.now.timeIntervalSince(cached.fetchedAt) < 20 * 60 {
            return cached
        }
        if let fresh = try? await client.fetchBoard() { return fresh }
        return client.cachedBoard()
    }

    /// Reload a little after the next scheduled run, and at least every three hours.
    static func nextReload(for board: Board?) -> Date {
        let fallback = Date.now.addingTimeInterval(3 * 3600)
        guard let board else { return .now.addingTimeInterval(30 * 60) }
        guard let next = board.status.nextRun?.addingTimeInterval(30 * 60), next > .now else { return fallback }
        return min(next, fallback)
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
