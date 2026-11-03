import Foundation

/// Everything the app shows, assembled from the public API and site data files.
public struct Board: Sendable {
    public let status: StatusDocument
    public let catalogue: CatalogueDocument?
    public let changes: [StatusChange]
    public let history: [String: [HistoryPoint]]
    public let worldTrend: [WorldPoint]
    public let fetchedAt: Date

    public init(
        status: StatusDocument,
        catalogue: CatalogueDocument?,
        changes: [StatusChange],
        history: [String: [HistoryPoint]],
        worldTrend: [WorldPoint],
        fetchedAt: Date
    ) {
        self.status = status
        self.catalogue = catalogue
        self.changes = changes.sorted { $0.t > $1.t }
        self.history = history
        self.worldTrend = worldTrend.sorted { $0.date < $1.date }
        self.fetchedAt = fetchedAt
        signalIndex = Dictionary(status.signals.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        entryIndex = Dictionary((catalogue?.signals ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        situationIndex = Dictionary(status.situations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private let signalIndex: [String: Signal]
    private let entryIndex: [String: CatalogueEntry]
    private let situationIndex: [String: Situation]

    // MARK: Lookup

    public var signals: [Signal] { status.signals }
    public var situations: [Situation] { status.situations }

    public func signal(_ id: String) -> Signal? { signalIndex[id] }
    public func entry(_ id: String) -> CatalogueEntry? { entryIndex[id] }
    public func situation(_ id: String) -> Situation? { situationIndex[id] }

    /// Domains in catalogue order; falls back to the order signals appear in.
    public var domains: [Domain] {
        if let domains = catalogue?.domains, !domains.isEmpty { return domains }
        var seen = Set<String>()
        return status.signals.compactMap { signal in
            guard seen.insert(signal.domain).inserted else { return nil }
            return Domain(id: signal.domain, name: signal.domainName ?? signal.domain.capitalized, short: nil, weight: nil)
        }
    }

    public func domain(_ id: String) -> Domain? { domains.first { $0.id == id } }

    public func domainName(_ id: String) -> String {
        domain(id)?.name ?? signals.first { $0.domain == id }?.domainName ?? id.capitalized
    }

    // MARK: Derived views

    /// Signals in a domain, most attention first, then by name.
    public func signals(inDomain id: String, at now: Date = .now) -> [Signal] {
        sorted(status.signals.filter { $0.domain == id }, at: now)
    }

    public func signals(withLevel level: Level, at now: Date = .now) -> [Signal] {
        sorted(status.signals.filter { $0.level(at: now) == level }, at: now)
    }

    public func signals(inSituation situation: Situation, at now: Date = .now) -> [Signal] {
        sorted(situation.signals.compactMap { signal($0) }, at: now)
    }

    public func situations(for signal: Signal) -> [Situation] {
        (signal.situations ?? []).compactMap { situation($0) }
    }

    public func sorted(_ signals: [Signal], at now: Date = .now) -> [Signal] {
        signals.sorted { a, b in
            let ra = a.level(at: now).rank, rb = b.level(at: now).rank
            if ra != rb { return ra < rb }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Counts by displayed level (so stale signals count as stale).
    public func counts(in signals: [Signal]? = nil, at now: Date = .now) -> [Level: Int] {
        var counts: [Level: Int] = [:]
        for signal in signals ?? status.signals { counts[signal.level(at: now), default: 0] += 1 }
        return counts
    }

    /// Changes in the last `hours`, newest first.
    public func recentChanges(hours: Double = 24, at now: Date = .now) -> [StatusChange] {
        let cutoff = now.addingTimeInterval(-hours * 3600)
        return changes.filter { $0.t >= cutoff }
    }

    public func history(for id: String) -> [HistoryPoint] {
        (history[id] ?? []).sorted { $0.date < $1.date }
    }

    /// Numeric points for a chart; empty when the signal has no key value series.
    public func valueSeries(for id: String) -> [HistoryPoint] {
        history(for: id).filter { $0.value != nil }
    }

    /// Whether the whole board is past its freshness window.
    public func isStale(at now: Date = .now) -> Bool {
        guard let validUntil = status.validUntil else { return false }
        return now > validUntil
    }

    /// Number of judged, measured and published statuses.
    public func basisCount(_ basis: Basis) -> Int {
        if let n = status.basisCounts?[basis.rawValue] { return n }
        return status.signals.filter { $0.basis == basis }.count
    }

    /// Simple text search across signals.
    public func search(_ query: String, at now: Date = .now) -> [Signal] {
        let terms = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return [] }
        let matches = status.signals.filter { signal in
            let haystack = [
                signal.name, signal.domainName ?? signal.domain, signal.value ?? "",
                signal.summary ?? "", entry(signal.id)?.why ?? "",
            ].joined(separator: " ").lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
        // Name matches first.
        return matches.sorted { a, b in
            let an = terms.allSatisfy { a.name.lowercased().contains($0) }
            let bn = terms.allSatisfy { b.name.lowercased().contains($0) }
            if an != bn { return an }
            return a.level(at: now).rank < b.level(at: now).rank
        }
    }
}
