#if DEBUG
import SwiftUI

/// Debug-only launch options for screenshots and UI checks. Pass them as scheme
/// arguments; iOS puts `-Key value` arguments into UserDefaults:
///
///     -CanaryPins oil,equity-stress,ftse     pin these signals at launch
///     -CanaryRoute canary://signal/oil        open a screen (any DeepLink URL)
///     -CanaryTab browse                       summary, browse, changes or search
///     -CanarySheet plus                       plus, settings or pins
///
/// Compiled out of release builds.
enum DebugLaunch {
    private static var defaults: UserDefaults { .standard }

    /// Runs before the stores are created.
    static func applyEarly() {
        if let pins = defaults.string(forKey: "CanaryPins") {
            SharedSettings.pinnedIDs = pins.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    /// Runs once the first board is on screen.
    @MainActor
    static func applyNavigation(_ router: Router) {
        if let tab = defaults.string(forKey: "CanaryTab") {
            switch tab {
            case "browse": router.tab = .browse
            case "changes": router.tab = .changes
            case "search": router.tab = .search
            default: router.tab = .summary
            }
        }
        if let route = defaults.string(forKey: "CanaryRoute"), let url = URL(string: route) {
            router.open(url)
        }
    }

    static var sheet: DebugSheet? {
        defaults.string(forKey: "CanarySheet").flatMap(DebugSheet.init(rawValue:))
    }
}

enum DebugSheet: String, Identifiable {
    case plus, settings, pins
    var id: String { rawValue }
}

/// Presents the sheet named by `-CanarySheet`.
struct DebugSheetPresenter: ViewModifier {
    @State private var sheet = DebugLaunch.sheet

    func body(content: Content) -> some View {
        content.sheet(item: $sheet) { sheet in
            switch sheet {
            case .plus: CanaryPlusView()
            case .settings: SettingsView()
            case .pins: PinEditorView()
            }
        }
    }
}
#endif
