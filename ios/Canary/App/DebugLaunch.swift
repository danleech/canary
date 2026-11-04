#if DEBUG
import SwiftUI

/// Debug-only launch options for screenshots and UI checks. Pass them as scheme
/// arguments; iOS puts `-Key value` arguments into UserDefaults:
///
///     -CanaryPins oil,equity-stress,ftse     pin these signals at launch
///     -CanaryRoute canary://signal/oil        open a screen (any DeepLink URL)
///     -CanaryTab browse                       summary, browse, changes or search
///     -CanarySheet plus                       plus, settings, pins or widgets
///     -CanaryPins none                        start with nothing pinned
///     -CanaryScroll 800                       scroll long pages down 800 points
///
/// Compiled out of release builds.
enum DebugLaunch {
    private static var defaults: UserDefaults { .standard }

    /// Runs before the stores are created.
    static func applyEarly() {
        if let pins = defaults.string(forKey: "CanaryPins") {
            SharedSettings.pinnedIDs = pins == "none" ? [] : pins.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
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

    /// `-CanaryScroll 800` scrolls long pages down by that many points.
    static var scrollOffset: CGFloat? {
        let value = defaults.double(forKey: "CanaryScroll")
        return value > 0 ? CGFloat(value) : nil
    }
}

/// Scrolls a page to `-CanaryScroll` once it has drawn.
struct DebugScroll: ViewModifier {
    @State private var position = ScrollPosition(edge: .top)

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .task {
                guard let offset = DebugLaunch.scrollOffset else { return }
                try? await Task.sleep(for: .milliseconds(800))
                position.scrollTo(y: offset)
            }
    }
}

enum DebugSheet: String, Identifiable {
    case plus, settings, pins, widgets, showcase
    var id: String { rawValue }
}

/// Presents the sheet named by `-CanarySheet` (the widget showcase full screen).
struct DebugSheetPresenter: ViewModifier {
    @State private var sheet = DebugLaunch.sheet == .showcase ? nil : DebugLaunch.sheet
    @State private var showsShowcase = DebugLaunch.sheet == .showcase

    func body(content: Content) -> some View {
        content
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .plus: CanaryPlusView()
                case .settings: SettingsView()
                case .pins: PinEditorView()
                case .widgets, .showcase: WidgetGalleryView()
                }
            }
            .fullScreenCover(isPresented: $showsShowcase) { WidgetShowcaseView() }
    }
}
#endif
