import Foundation

/// Settings the app writes and the widget reads, kept in the App Group.
public enum SharedSettings {
    private static var defaults: UserDefaults { AppConstants.sharedDefaults }

    // MARK: Pinned signals

    /// Pinned signal ids, in the order the person arranged them.
    public static var pinnedIDs: [String] {
        get { defaults.stringArray(forKey: "pins.ids") ?? [] }
        set { defaults.set(newValue, forKey: "pins.ids") }
    }

    // MARK: Canary+

    /// Mirror of the StoreKit entitlement so the widget can check it cheaply.
    /// The app re-derives it from StoreKit on every launch.
    public static var isPlus: Bool {
        get { defaults.bool(forKey: "plus.active") }
        set { defaults.set(newValue, forKey: "plus.active") }
    }

    // MARK: Alerts

    public static var alertsEnabled: Bool {
        get { defaults.bool(forKey: "alerts.enabled") }
        set { defaults.set(newValue, forKey: "alerts.enabled") }
    }

    public static var alertScope: AlertScope {
        get { AlertScope(rawValue: defaults.string(forKey: "alerts.scope") ?? "") ?? .pinned }
        set { defaults.set(newValue.rawValue, forKey: "alerts.scope") }
    }

    /// Time of the newest change already seen, so no change is announced twice.
    public static var lastSeenChange: Date? {
        get {
            let stamp = defaults.double(forKey: "alerts.lastSeenChange")
            return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "alerts.lastSeenChange") }
    }
}

/// Which status changes produce an alert.
public enum AlertScope: String, CaseIterable, Identifiable, Sendable {
    case pinned
    case pinnedAndAlerts
    case everything

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .pinned: "Pinned Signals"
        case .pinnedAndAlerts: "Pinned Signals and Any New Alert"
        case .everything: "Every Change"
        }
    }

    public func includes(_ change: StatusChange, pinned: Set<String>) -> Bool {
        switch self {
        case .pinned: pinned.contains(change.id)
        case .pinnedAndAlerts: pinned.contains(change.id) || change.to == .alert
        case .everything: true
        }
    }
}

/// What Canary+ unlocks. Tune the business model here.
public enum PlusFeature: CaseIterable, Sendable {
    case alerts
    case unlimitedPins
    case signalWidgets

    /// Pins available without Canary+.
    public static let freePinLimit = 3

    public var title: String {
        switch self {
        case .alerts: "Alerts when signals change level"
        case .unlimitedPins: "Pin as many signals as you like"
        case .signalWidgets: "Signal and Pinned widgets, on the Home and Lock Screen"
        }
    }

    public var symbol: String {
        switch self {
        case .alerts: "bell.badge"
        case .unlimitedPins: "pin"
        case .signalWidgets: "rectangle.stack"
        }
    }
}
