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
