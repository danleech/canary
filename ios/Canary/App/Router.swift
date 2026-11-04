import Foundation
import Observation

enum AppTab: Hashable {
    case summary
    case browse
    case changes
    case search
    /// A Browse destination shown as its own item in the sidebar, as Health lists
    /// its categories on iPhone Duo's inner display.
    case browseSection(BrowseSelection)
}

/// A screen that can be pushed onto any tab's navigation stack.
enum Route: Hashable {
    case signal(String)
    case situation(String)
    case domain(String)
    case world
    case situations
    case allSignals
    case level(Level)
}

/// A Browse item: pushed from Browse's tiles in the tab bar layout, or listed
/// directly in the sidebar layout.
enum BrowseSelection: Hashable {
    case allSignals
    case situations
    case domain(String)

    var route: Route {
        switch self {
        case .allSignals: .allSignals
        case .situations: .situations
        case .domain(let id): .domain(id)
        }
    }

    init?(route: Route) {
        switch route {
        case .allSignals: self = .allSignals
        case .situations: self = .situations
        case .domain(let id): self = .domain(id)
        default: return nil
        }
    }
}

/// Navigation state for every tab, so deep links from widgets, notifications
/// and Siri land in the right place, and folding iPhone Duo keeps the same
/// screen open.
@MainActor
@Observable
final class Router {
    static let shared = Router()

    var tab: AppTab = .summary
    var summaryPath: [Route] = []
    var browsePath: [Route] = []
    var changesPath: [Route] = []
    var searchPath: [Route] = []
    /// Navigation stacks of the sidebar's Browse items.
    var sectionPaths: [BrowseSelection: [Route]] = [:]

    func open(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        open(link)
    }

    func open(_ link: DeepLink) {
        tab = .summary
        switch link {
        case .world: summaryPath = [.world]
        case .signal(let id): summaryPath = [.signal(id)]
        case .situation(let id): summaryPath = [.situation(id)]
        case .domain(let id):
            browsePath = [.domain(id)]
            sectionPaths[.domain(id)] = []
            tab = .browse
        }
    }

    /// The Browse item at the bottom of Browse's stack, if any.
    private var browseRoot: BrowseSelection? {
        browsePath.first.flatMap(BrowseSelection.init(route:))
    }

    /// The tab to show for the current layout. Browse is one tab in the tab bar,
    /// and its items are separate entries in the sidebar.
    func displayedTab(usesSidebar: Bool) -> AppTab {
        switch tab {
        case .browse where usesSidebar: .browseSection(browseRoot ?? .allSignals)
        case .browseSection where !usesSidebar: .browse
        default: tab
        }
    }

    /// Keeps the selection valid when the app moves between the tab bar and the
    /// sidebar, for example when iPhone Duo is folded or unfolded. Browse is a
    /// tab in the tab bar; in the sidebar its items are listed directly. The
    /// open item and anything pushed on it carry across.
    func adapt(usesSidebar: Bool) {
        switch tab {
        case .browse where usesSidebar:
            if let root = browseRoot {
                sectionPaths[root] = Array(browsePath.dropFirst())
                tab = .browseSection(root)
            } else {
                sectionPaths[.allSignals] = browsePath
                tab = .browseSection(.allSignals)
            }
        case .browseSection(let selection) where !usesSidebar:
            browsePath = [selection.route] + (sectionPaths[selection] ?? [])
            tab = .browse
        default:
            break
        }
    }
}
