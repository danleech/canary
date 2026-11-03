import BackgroundTasks
import Foundation
import UserNotifications
import WidgetKit

/// On-device alerts. While the app is in the background, iOS occasionally wakes
/// it to check for status changes; when a change matches the person's alert
/// scope, the app posts a local notification. iOS decides when that happens,
/// so an alert can arrive some hours after the board changes. No server, no
/// account, and nothing about the person leaves the device.
@MainActor
final class AlertService {
    static let shared = AlertService()

    private let center = UNUserNotificationCenter.current()

    // MARK: Permission

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Asks for permission in context, when the person turns alerts on.
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: Scheduling

    /// Asks iOS to wake the app a little after the next scheduled board update.
    func scheduleRefresh(after nextRun: Date?) {
        guard SharedSettings.alertsEnabled, SharedSettings.isPlus else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: AppConstants.refreshTaskID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: AppConstants.refreshTaskID)
        // A run takes about 20 minutes to publish; ask for no sooner than 15 minutes from now.
        let afterRun = (nextRun ?? .now.addingTimeInterval(6 * 3600)).addingTimeInterval(30 * 60)
        request.earliestBeginDate = max(afterRun, .now.addingTimeInterval(15 * 60))
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: Checking

    /// Runs in the background task: fetch, compare, notify, reschedule.
    func handleBackgroundRefresh() async {
        guard let board = try? await CanaryClient().fetchBoard() else {
            scheduleRefresh(after: nil)
            return
        }
        let fresh = unseenChanges(in: board)
        markSeen(board)
        WidgetCenter.shared.reloadAllTimelines()
        if SharedSettings.alertsEnabled, SharedSettings.isPlus {
            let pinned = Set(SharedSettings.pinnedIDs)
            let matching = fresh.filter { SharedSettings.alertScope.includes($0, pinned: pinned) }
            await post(matching)
        }
        scheduleRefresh(after: board.status.nextRun)
    }

    /// Records the newest change as seen. Called after every fetch, so changes
    /// the person has already seen in the app are never announced later.
    func markSeen(_ board: Board) {
        guard let newest = board.changes.first?.t else { return }
        if let seen = SharedSettings.lastSeenChange, seen >= newest { return }
        SharedSettings.lastSeenChange = newest
    }

    private func unseenChanges(in board: Board) -> [StatusChange] {
        // First check after install: start from now rather than announcing history.
        guard let seen = SharedSettings.lastSeenChange else { return [] }
        return board.changes.filter { $0.t > seen }
    }

    // MARK: Notifications

    private func post(_ changes: [StatusChange]) async {
        guard !changes.isEmpty, await authorizationStatus() == .authorized else { return }
        if changes.count <= 3 {
            for change in changes { await add(content(for: change), id: change.key) }
        } else {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(changes.count) signals changed level")
            content.body = changes.prefix(6).map { "\($0.name): \($0.from.label) → \($0.to.label)" }
                .joined(separator: "\n")
            content.threadIdentifier = "canary.changes"
            content.userInfo = ["link": DeepLink.world.url.absoluteString]
            await add(content, id: "summary-\(changes[0].key)")
        }
    }

    private func content(for change: StatusChange) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = change.isEscalation
            ? String(localized: "\(change.name) moved up to \(change.to.label)")
            : String(localized: "\(change.name) eased to \(change.to.label)")
        content.body = change.reason ?? String(localized: "Was \(change.from.label).")
        content.threadIdentifier = "canary.changes"
        content.userInfo = ["link": DeepLink.signal(change.id).url.absoluteString]
        return content
    }

    private func add(_ content: UNMutableNotificationContent, id: String) async {
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await center.add(request)
    }
}
