import Foundation

/// Attention level for a signal, situation or emerging risk.
///
/// The API sends `alert`, `watch`, `normal` or `pending`. `stale` is never sent:
/// the app works it out when a signal has not been verified within its freshness
/// window (`stale_after`), as the website does.
public enum Level: String, Codable, CaseIterable, Hashable, Sendable {
    case alert
    case watch
    case normal
    case stale
    case pending

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Level(apiValue: raw)
    }

    /// Maps both the public vocabulary and the internal history codes.
    public init(apiValue raw: String) {
        switch raw.lowercased() {
        case "alert", "red", "r": self = .alert
        case "watch", "amber", "a": self = .watch
        case "normal", "green", "g": self = .normal
        case "stale", "s": self = .stale
        default: self = .pending
        }
    }

    /// Sort order: most attention first.
    public var rank: Int {
        switch self {
        case .alert: 0
        case .watch: 1
        case .normal: 2
        case .stale: 3
        case .pending: 4
        }
    }

    public var label: String {
        switch self {
        case .alert: "Alert"
        case .watch: "Watch"
        case .normal: "Normal"
        case .stale: "Stale"
        case .pending: "Pending"
        }
    }

    /// One line on what the level means, from the charter's status semantics.
    public var meaning: String {
        switch self {
        case .alert: "Acute or material risk happening now. If it could affect you, look into it."
        case .watch: "Elevated or deteriorating. Worth keeping an eye on."
        case .normal: "Within normal range. Background noise."
        case .stale: "Not verified within its freshness window."
        case .pending: "Not yet assessed."
        }
    }
}

/// Direction of risk over about a week. Not the direction of the number.
public enum Trend: String, Codable, Hashable, Sendable {
    case worsening
    case stable
    case improving
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Trend(rawValue: raw.lowercased()) ?? .unknown
    }

    public var label: String {
        switch self {
        case .worsening: "Worsening"
        case .stable: "Stable"
        case .improving: "Improving"
        case .unknown: "No trend"
        }
    }

    public var symbol: String {
        switch self {
        case .worsening: "arrow.up.right"
        case .stable: "arrow.right"
        case .improving: "arrow.down.right"
        case .unknown: "minus"
        }
    }
}

/// How a status was set.
public enum Basis: String, Codable, Hashable, Sendable {
    case measured
    case published
    case judged
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Basis(rawValue: raw.lowercased()) ?? .unknown
    }

    public var label: String {
        switch self {
        case .measured: "Measured"
        case .published: "Published figure"
        case .judged: "AI judgement"
        case .unknown: "Not recorded"
        }
    }

    public var symbol: String {
        switch self {
        case .measured: "ruler"
        case .published: "building.columns"
        case .judged: "sparkles"
        case .unknown: "questionmark.circle"
        }
    }

    public var explanation: String {
        switch self {
        case .measured:
            "Set by a fixed rule applied to open data, so anyone can reproduce it."
        case .published:
            "Follows a figure or classification published by a named official body."
        case .judged:
            "The AI assessor's reading of this run's sources against the published rubric. Weigh it with more caution than a measured status."
        case .unknown:
            "How this status was set was not recorded."
        }
    }
}

/// How fast the underlying situation moves.
public enum Horizon: String, Codable, Hashable, Sendable {
    case acute
    case seasonal
    case chronic
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Horizon(rawValue: raw.lowercased()) ?? .unknown
    }
}
