import Foundation

// MARK: - status.json

/// `api/v1/status.json`: the whole board.
public struct StatusDocument: Codable, Hashable, Sendable {
    public var version: String?
    public var asOf: Date
    public var validUntil: Date?
    public var nextRun: Date?
    public var assessedBy: String?
    public var disclaimer: String?
    public var headline: String?
    public var licence: Licence?
    public var world: WorldState
    public var basisCounts: [String: Int]?
    public var situations: [Situation]
    public var emerging: [EmergingRisk]
    public var signals: [Signal]

    enum CodingKeys: String, CodingKey {
        case version, asOf, validUntil, nextRun, assessedBy, disclaimer, headline, licence
        case world, basisCounts, situations, emerging, signals
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(String.self, forKey: .version)
        asOf = try c.decode(Date.self, forKey: .asOf)
        validUntil = try c.decodeIfPresent(Date.self, forKey: .validUntil)
        nextRun = try c.decodeIfPresent(Date.self, forKey: .nextRun)
        assessedBy = try c.decodeIfPresent(String.self, forKey: .assessedBy)
        disclaimer = try c.decodeIfPresent(String.self, forKey: .disclaimer)
        headline = try c.decodeIfPresent(String.self, forKey: .headline)
        licence = try? c.decodeIfPresent(Licence.self, forKey: .licence)
        world = try c.decode(WorldState.self, forKey: .world)
        basisCounts = try? c.decodeIfPresent([String: Int].self, forKey: .basisCounts)
        situations = (try? c.decodeIfPresent([Situation].self, forKey: .situations)) ?? []
        emerging = (try? c.decodeIfPresent([EmergingRisk].self, forKey: .emerging)) ?? []
        signals = try c.decode([Signal].self, forKey: .signals)
    }
}

public struct Licence: Codable, Hashable, Sendable {
    public var name: String
    public var url: URL?
    public var attribution: String?
}

/// The headline World State index (0–100) and its inputs.
public struct WorldState: Codable, Hashable, Sendable {
    public var score: Int?
    public var band: String?
    public var counts: [String: Int]?
    public var byDomain: [String: Int]?
    public var method: Int?
    public var methodUrl: URL?

    public var bandKind: WorldBand { WorldBand(name: band, score: score) }
}

/// Bands used by the pipeline (`canary.py`): Calm < 25, Unsettled < 40,
/// Strained < 60, otherwise Severe.
public enum WorldBand: String, CaseIterable, Sendable {
    case calm = "Calm"
    case unsettled = "Unsettled"
    case strained = "Strained"
    case severe = "Severe"
    case unknown = "—"

    public init(name: String?, score: Int?) {
        if let name, let band = WorldBand(rawValue: name) {
            self = band
        } else if let score {
            self = score < 25 ? .calm : score < 40 ? .unsettled : score < 60 ? .strained : .severe
        } else {
            self = .unknown
        }
    }

    /// Lower edge of each band on the 0–100 scale.
    public static let thresholds: [BandThreshold] = [
        BandThreshold(band: .calm, from: 0),
        BandThreshold(band: .unsettled, from: 25),
        BandThreshold(band: .strained, from: 40),
        BandThreshold(band: .severe, from: 60),
    ]
}

public struct BandThreshold: Hashable, Sendable {
    public let band: WorldBand
    public let from: Int
}

/// One risk signal on the board.
public struct Signal: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var domain: String
    public var domainName: String?
    public var status: Level
    public var trend: Trend?
    public var horizon: Horizon?
    public var tier: String?
    public var value: String?
    public var valueNum: Double?
    public var summary: String?
    public var state: String?
    public var forYou: String?
    public var rubricHit: String?
    public var situations: [String]?
    public var basis: Basis?
    public var basisDetail: String?
    public var basisBy: String?
    public var checkedAt: Date?
    public var changedAt: Date?
    public var staleAfter: Date?
    public var sources: [Source]?
    public var url: URL?
    /// Set by the app, never by the API: true when this signal's figures come
    /// from market data Canary can't republish in a paid app, so its value,
    /// series and rule inputs are withheld (see `RestrictedData`).
    public var figuresWithheld: Bool?

    public var withholdsFigures: Bool { figuresWithheld == true }

    /// The level to show now: `stale` once `stale_after` has passed.
    public func level(at now: Date = .now) -> Level {
        if let staleAfter, now > staleAfter, status != .pending { return .stale }
        return status
    }
}

public struct Source: Codable, Hashable, Sendable, Identifiable {
    public var title: String
    public var url: URL
    public var date: String?

    public var id: URL { url }

    /// The publisher's host without `www.`, for display.
    public var host: String {
        let host = url.host() ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// A cross-domain event that groups several signals (for example a war moving
/// oil, gas, shipping and freight). Situations never change a signal's status.
public struct Situation: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var status: Level
    public var trend: Trend?
    public var summary: String?
    public var signals: [String]
}

/// A risk outside the catalogue that the assessor flagged (at most three).
public struct EmergingRisk: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var status: Level
    public var summary: String
    public var sources: [Source]?

    public var id: String { name }
}

// MARK: - catalogue.json

/// `api/v1/catalogue.json`: signal definitions and rubrics.
public struct CatalogueDocument: Codable, Hashable, Sendable {
    public var version: String?
    public var domains: [Domain]
    public var signals: [CatalogueEntry]
}

public struct Domain: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var short: String?
    public var weight: Double?
}

public struct CatalogueEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var domain: String
    public var tier: String?
    public var horizon: Horizon?
    /// Keys into `data/metrics.json` for the numbers behind this signal.
    public var metrics: [String]?
    public var why: String?
    public var drivers: String?
    public var rubric: Rubric?
}

/// Written thresholds for each level.
public struct Rubric: Codable, Hashable, Sendable {
    public var alert: String?
    public var watch: String?
    public var normal: String?

    public func text(for level: Level) -> String? {
        switch level {
        case .alert: alert
        case .watch: watch
        case .normal: normal
        case .stale, .pending: nil
        }
    }
}

// MARK: - changes.json

/// `api/v1/changes.json`: recent status changes, newest first.
public struct ChangesDocument: Codable, Hashable, Sendable {
    public var asOf: Date?
    public var changes: [StatusChange]
}

public struct StatusChange: Codable, Hashable, Identifiable, Sendable {
    public var t: Date
    public var id: String
    public var name: String
    public var from: Level
    public var to: Level
    public var reason: String?
    public var url: URL?

    /// Stable identity for lists: a signal can change more than once.
    public var key: String { "\(id)@\(t.timeIntervalSince1970)" }

    /// Whether the move raised the attention level.
    public var isEscalation: Bool { to.rank < from.rank }
}

// MARK: - history.json and world.json (site data files)

/// One check of one signal: when, the level, and the key value if it has one.
public struct HistoryPoint: Decodable, Hashable, Sendable {
    public var date: Date
    public var level: Level
    public var value: Double?

    public init(date: Date, level: Level, value: Double?) {
        self.date = date
        self.level = level
        self.value = value
    }

    /// Decodes the compact `["2026-11-03T18:02:27Z", "a", 21.15]` form.
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let stamp = try c.decode(String.self)
        guard let date = CanaryDates.parse(stamp) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date \(stamp)")
        }
        self.date = date
        level = Level(apiValue: (try? c.decode(String.self)) ?? "")
        value = c.isAtEnd ? nil : (try? c.decodeIfPresent(Double.self)) ?? nil
    }
}

/// One point of the World State index over time.
public struct WorldPoint: Decodable, Hashable, Sendable {
    public var date: Date
    public var score: Int

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let stamp = try c.decode(String.self)
        guard let date = CanaryDates.parse(stamp) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date \(stamp)")
        }
        self.date = date
        score = try c.decode(Int.self)
    }
}

// MARK: - Dates

public enum CanaryDates {
    /// Parses ISO 8601 timestamps with or without fractional seconds.
    public static func parse(_ string: String) -> Date? {
        if let date = try? Date(string, strategy: .iso8601) { return date }
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return try? fractional.parse(string)
    }

    public static func decoder(snakeCase: Bool) -> JSONDecoder {
        let decoder = JSONDecoder()
        if snakeCase { decoder.keyDecodingStrategy = .convertFromSnakeCase }
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let string = try c.decode(String.self)
            guard let date = parse(string) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date \(string)")
            }
            return date
        }
        return decoder
    }
}

// MARK: - metrics.json (site data file)

/// `data/metrics.json`: only what the app needs, which is where each metric
/// comes from and whether its licence allows republishing.
public struct MetricsDocument: Decodable, Sendable {
    public var metrics: [String: MetricInfo]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Skip entries that don't decode rather than fail the file.
        let raw = try c.decode([String: FailableMetric].self, forKey: .metrics)
        metrics = raw.compactMapValues(\.info)
    }

    enum CodingKeys: String, CodingKey { case metrics }

    private struct FailableMetric: Decodable {
        let info: MetricInfo?
        init(from decoder: Decoder) throws { info = try? MetricInfo(from: decoder) }
    }
}

public struct MetricInfo: Decodable, Sendable {
    public var source: String?
    public var licence: String?
    public var note: String?
}
