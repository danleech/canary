import AppIntents
import Foundation

/// A Canary signal, for Siri, Shortcuts, Spotlight and widget configuration.
public struct SignalEntity: AppEntity, Identifiable, Hashable, Sendable {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Signal"
    public static let defaultQuery = SignalQuery()

    public let id: String
    public let name: String
    public let domainID: String
    public let domainName: String

    public init(id: String, name: String, domainID: String, domainName: String) {
        self.id = id
        self.name = name
        self.domainID = domainID
        self.domainName = domainName
    }

    public init(_ signal: Signal) {
        self.init(id: signal.id, name: signal.name, domainID: signal.domain,
                  domainName: signal.domainName ?? signal.domain.capitalized)
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(domainName)",
            image: .init(systemName: DomainStyle.symbol(for: domainID))
        )
    }
}

public struct SignalQuery: EntityStringQuery, Sendable {
    public init() {}

    public func entities(for identifiers: [SignalEntity.ID]) async throws -> [SignalEntity] {
        let board = try await IntentBoard.load()
        return identifiers.compactMap { board.signal($0).map(SignalEntity.init) }
    }

    public func entities(matching string: String) async throws -> [SignalEntity] {
        let board = try await IntentBoard.load()
        return board.search(string).map(SignalEntity.init)
    }

    public func suggestedEntities() async throws -> [SignalEntity] {
        let board = try await IntentBoard.load()
        // Pinned first, then everything on Alert, then the rest.
        let pinned = SharedSettings.pinnedIDs.compactMap { board.signal($0) }
        let rest = board.sorted(board.signals).filter { signal in !pinned.contains { $0.id == signal.id } }
        return (pinned + rest).map(SignalEntity.init)
    }
}

/// Board access for intents and widgets: a recent saved copy if there is one,
/// otherwise a fresh fetch.
public enum IntentBoard {
    public static var cached: Board? { CanaryClient().cachedBoard() }

    public static func load(maxAge: TimeInterval = 30 * 60) async throws -> Board {
        let client = CanaryClient()
        if let cached = client.cachedBoard(), Date.now.timeIntervalSince(cached.fetchedAt) < maxAge {
            return cached
        }
        do {
            return try await client.fetchBoard()
        } catch {
            if let cached = client.cachedBoard() { return cached }
            throw error
        }
    }
}
