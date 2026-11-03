import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reads Canary's public, read-only API. No account, no key, no personal data:
/// requests carry only a generic app User-Agent.
public struct CanaryClient: Sendable {
    public static let baseURL = URL(string: "https://canary.danleech.com")!

    /// The files the app reads, and whether a board can be built without them.
    public enum Resource: String, CaseIterable, Sendable {
        case status = "api/v1/status.json"
        case catalogue = "api/v1/catalogue.json"
        case changes = "api/v1/changes.json"
        case history = "data/history.json"
        case world = "data/world.json"

        var isRequired: Bool { self == .status }
        var cacheName: String { rawValue.replacingOccurrences(of: "/", with: "_") }
    }

    public enum ClientError: LocalizedError {
        case badResponse(Int)
        case offline

        public var errorDescription: String? {
            switch self {
            case .badResponse(let code): "Canary's server replied with an error (\(code))."
            case .offline: "You're offline, and there's no saved copy of the board yet."
            }
        }
    }

    private let session: URLSession
    private let cache: BoardCache?

    public init(cache: BoardCache? = .shared, timeout: TimeInterval = 20) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.requestCachePolicy = .reloadRevalidatingCacheData
        config.httpAdditionalHeaders = ["User-Agent": "CanaryApp/1.0 (iOS)", "Accept": "application/json"]
        session = URLSession(configuration: config)
        self.cache = cache
    }

    /// Fetches every file, saves good copies, and builds a board.
    /// Optional files fall back to the last saved copy, then to empty.
    public func fetchBoard() async throws -> Board {
        async let status = data(for: .status)
        async let catalogue = optionalData(for: .catalogue)
        async let changes = optionalData(for: .changes)
        async let history = optionalData(for: .history)
        async let world = optionalData(for: .world)

        let statusData = try await status
        let catalogueData = await catalogue
        let changesData = await changes
        let historyData = await history
        let worldData = await world

        let files: [Resource: Data] = [
            .status: statusData,
            .catalogue: catalogueData ?? cache?.read(.catalogue) ?? Data(),
            .changes: changesData ?? cache?.read(.changes) ?? Data(),
            .history: historyData ?? cache?.read(.history) ?? Data(),
            .world: worldData ?? cache?.read(.world) ?? Data(),
        ]
        let board = try Self.makeBoard(files, fetchedAt: .now)
        // Only save once everything decodes, so a bad deploy can't overwrite a good copy.
        for (resource, bytes) in files where !bytes.isEmpty { cache?.write(bytes, for: resource) }
        cache?.markFetched(.now)
        return board
    }

    /// The last saved board, for instant launch and offline use.
    public func cachedBoard() -> Board? {
        guard let cache, let status = cache.read(.status) else { return nil }
        var files: [Resource: Data] = [.status: status]
        for resource in Resource.allCases where resource != .status {
            files[resource] = cache.read(resource) ?? Data()
        }
        return try? Self.makeBoard(files, fetchedAt: cache.lastFetched ?? .distantPast)
    }

    // MARK: Decoding

    public static func makeBoard(_ files: [Resource: Data], fetchedAt: Date) throws -> Board {
        let api = CanaryDates.decoder(snakeCase: true)
        let plain = CanaryDates.decoder(snakeCase: false)
        let status = try api.decode(StatusDocument.self, from: files[.status] ?? Data())
        let catalogue = files[.catalogue].flatMap { try? api.decode(CatalogueDocument.self, from: $0) }
        let changes = files[.changes].flatMap { try? api.decode(ChangesDocument.self, from: $0) }?.changes ?? []
        // History keys are signal ids; decode without key conversion.
        let history = files[.history].flatMap { try? plain.decode([String: [FailableHistoryPoint]].self, from: $0) }?
            .mapValues { $0.compactMap(\.point) } ?? [:]
        let world = files[.world].flatMap { try? plain.decode([FailableWorldPoint].self, from: $0) }?
            .compactMap(\.point) ?? []
        return Board(status: status, catalogue: catalogue, changes: changes, history: history,
                     worldTrend: world, fetchedAt: fetchedAt)
    }

    // MARK: Transport

    private func data(for resource: Resource) async throws -> Data {
        let url = Self.baseURL.appending(path: resource.rawValue)
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ClientError.badResponse(http.statusCode)
            }
            return data
        } catch let error as URLError where resource.isRequired {
            let offline: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed]
            if offline.contains(error.code) {
                throw ClientError.offline
            }
            throw error
        }
    }

    private func optionalData(for resource: Resource) async -> Data? {
        try? await data(for: resource)
    }
}

/// Skips a malformed history point instead of failing the whole file.
private struct FailableHistoryPoint: Decodable {
    let point: HistoryPoint?
    init(from decoder: Decoder) throws { point = try? HistoryPoint(from: decoder) }
}

private struct FailableWorldPoint: Decodable {
    let point: WorldPoint?
    init(from decoder: Decoder) throws { point = try? WorldPoint(from: decoder) }
}
