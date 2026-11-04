import SwiftUI
import UserNotifications

@main
struct CanaryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @State private var store = BoardStore()
    @State private var pins: PinStore
    @State private var plus = PlusStore()
    @State private var router = Router.shared

    init() {
        #if DEBUG
        DebugLaunch.applyEarly()
        #endif
        // Created after any debug pins are applied, so it reads them.
        _pins = State(initialValue: PinStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(pins)
                .environment(plus)
                .environment(router)
                .onOpenURL { router.open($0) }
                .task {
                    #if DEBUG
                    // Before the refresh, so screens open at once from the saved board.
                    DebugLaunch.applyNavigation(router)
                    #endif
                    plus.start()
                    store.startClock()
                    await store.refresh()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await store.refresh(minimumInterval: 5 * 60) }
            case .background:
                AlertService.shared.scheduleRefresh(after: store.board?.status.nextRun)
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(AppConstants.refreshTaskID)) {
            await AlertService.shared.handleBackgroundRefresh()
        }
    }
}

/// Handles taps on alert notifications.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let link = response.notification.request.content.userInfo["link"] as? String,
              let url = URL(string: link) else { return }
        await MainActor.run { Router.shared.open(url) }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
