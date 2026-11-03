import Foundation
import Observation
import WidgetKit

/// Holds the current board for the whole app. Shows the saved copy at once,
/// then refreshes from the network.
@MainActor
@Observable
final class BoardStore {
    enum Phase: Equatable {
        case idle
        case loading
        case failed(String)
    }

    private(set) var board: Board?
    private(set) var phase: Phase = .idle
    /// Ticks once a minute so stale flags and relative times stay current.
    private(set) var now: Date = .now

    private let client = CanaryClient()
    private var clock: Task<Void, Never>?

    init() {
        board = client.cachedBoard()
    }

    var isLoading: Bool { phase == .loading }

    var errorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    /// Refreshes unless a refresh happened in the last `minimumInterval` seconds.
    func refresh(minimumInterval: TimeInterval = 0) async {
        if let board, Date.now.timeIntervalSince(board.fetchedAt) < minimumInterval { return }
        guard phase != .loading else { return }
        phase = .loading
        do {
            let fresh = try await client.fetchBoard()
            board = fresh
            phase = .idle
            now = .now
            AlertService.shared.markSeen(fresh)
            WidgetCenter.shared.reloadAllTimelines()
            CanaryShortcuts.updateAppShortcutParameters()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func startClock() {
        guard clock == nil else { return }
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.now = .now
            }
        }
    }
}
