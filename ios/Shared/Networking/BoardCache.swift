import Foundation

/// Identifiers shared by the app and its widget extension.
public enum AppConstants {
    /// Must match the App Group in both targets' entitlements.
    public static let appGroup = "group.com.danleech.canary"
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in the app's Info.plist.
    public static let refreshTaskID = "com.danleech.canary.refresh"
    public static let urlScheme = "canary"
    public static let websiteURL = URL(string: "https://canary.danleech.com")!
    public static let methodologyURL = URL(string: "https://canary.danleech.com/methodology")!
    public static let indexMethodURL = URL(string: "https://canary.danleech.com/methodology#index")!
    /// Required for a subscription app. Publish this page before submitting.
    public static let privacyURL = URL(string: "https://canary.danleech.com/privacy")!
    public static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Settings shared with the widget. Falls back to standard defaults if the
    /// App Group isn't provisioned (for example before a team is set in Xcode).
    public static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
}

/// Saves the last good copy of each API file, in the App Group container when
/// available so the widget can show the board instantly.
public final class BoardCache: @unchecked Sendable {
    public static let shared = BoardCache()

    private let directory: URL
    private let lock = NSLock()

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else if let group = Self.groupContainer() {
            self.directory = group.appending(path: "BoardCache", directoryHint: .isDirectory)
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appending(path: "BoardCache", directoryHint: .isDirectory)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func read(_ resource: CanaryClient.Resource) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return try? Data(contentsOf: url(for: resource))
    }

    func write(_ data: Data, for resource: CanaryClient.Resource) {
        lock.lock(); defer { lock.unlock() }
        try? data.write(to: url(for: resource), options: .atomic)
    }

    public var lastFetched: Date? {
        let stamp = AppConstants.sharedDefaults.double(forKey: "cache.lastFetched")
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    func markFetched(_ date: Date) {
        AppConstants.sharedDefaults.set(date.timeIntervalSince1970, forKey: "cache.lastFetched")
    }

    private static func groupContainer() -> URL? {
        #if canImport(Darwin)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroup)
        #else
        nil
        #endif
    }

    private func url(for resource: CanaryClient.Resource) -> URL {
        directory.appending(path: resource.cacheName)
    }
}
