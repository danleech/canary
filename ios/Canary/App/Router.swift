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
    case level(Level)
}

/// What Browse's own list has selected (tab bar layout), or which Browse item
/// the sidebar shows (sidebar layout).
enum BrowseSelection: Hashable {
    case allSignals
    case situations
    case domain(String)
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
    var browseSelection: BrowseSelection?
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
            browseSelection = .domain(id)
            browsePath = []
            sectionPaths[.domain(id)] = []
            tab = .browse
        }
    }

    /// Selects a Browse item from Browse's own list, starting its stack afresh.
    func selectBrowse(_ selection: BrowseSelection?) {
        guard selection != browseSelection else { return }
        browseSelection = selection
        browsePath = []
    }

    /// The tab to show for the current layout. Browse is one tab in the tab bar,
    /// and its items are separate entries in the sidebar.
    func displayedTab(usesSidebar: Bool) -> AppTab {
        switch tab {
        case .browse where usesSidebar: .browseSection(browseSelection ?? .allSignals)
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
            let selection = browseSelection ?? .allSignals
            sectionPaths[selection] = browsePath
            tab = .browseSection(selection)
        case .browseSection(let selection) where !usesSidebar:
            browseSelection = selection
            browsePath = sectionPaths[selection] ?? []
            tab = .browse
        default:
            break
        }
    }
}
