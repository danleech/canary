import Foundation
import Observation

enum AppTab: Hashable {
    case summary
    case browse
    case changes
    case search
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

/// What Browse's sidebar has selected.
enum BrowseSelection: Hashable {
    case allSignals
    case situations
    case domain(String)
}

/// Navigation state for every tab, so deep links from widgets, notifications
/// and Siri land in the right place.
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
            tab = .browse
            browseSelection = .domain(id)
            browsePath = []
        }
    }
}
