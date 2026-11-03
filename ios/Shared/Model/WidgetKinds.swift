import Foundation

/// Widget kind identifiers, shared so the app can reload a widget's timeline.
public enum WidgetKinds {
    public static let world = "WorldStateWidget"
    public static let signal = "SignalWidget"
    public static let pinned = "PinnedWidget"
}

/// Deep links used by widgets and notifications: `canary://signal/oil`,
/// `canary://situation/us-iran-war`, `canary://world`.
public enum DeepLink: Hashable, Sendable {
    case world
    case signal(String)
    case situation(String)
    case domain(String)

    public var url: URL {
        let scheme = AppConstants.urlScheme
        switch self {
        case .world: return URL(string: "\(scheme)://world")!
        case .signal(let id): return URL(string: "\(scheme)://signal/\(id)")!
        case .situation(let id): return URL(string: "\(scheme)://situation/\(id)")!
        case .domain(let id): return URL(string: "\(scheme)://domain/\(id)")!
        }
    }

    public init?(url: URL) {
        // Also accept the website's own signal pages: https://canary.danleech.com/s/{id}
        if url.scheme == "https", url.host() == AppConstants.websiteURL.host() {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count == 2, parts[0] == "s" { self = .signal(parts[1]); return }
            return nil
        }
        guard url.scheme == AppConstants.urlScheme, let host = url.host() else { return nil }
        let id = url.pathComponents.filter { $0 != "/" }.first
        switch (host, id) {
        case ("world", _): self = .world
        case ("signal", let id?): self = .signal(id)
        case ("situation", let id?): self = .situation(id)
        case ("domain", let id?): self = .domain(id)
        default: return nil
        }
    }
}
