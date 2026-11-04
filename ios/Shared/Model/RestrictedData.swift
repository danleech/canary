import Foundation

/// Market data Canary uses to set levels but can't republish in a paid app.
///
/// The website shows derived figures from Yahoo Finance, ICE BofA (via FRED)
/// and Cboe under their terms for a free, non-commercial board. The app is a
/// paid product, so for signals built on those sources it shows the level, the
/// level history and the written assessment, and withholds the live value, the
/// value series, the rule text and the rule inputs, all of which carry the
/// figures.
///
/// Which metrics are restricted comes from `data/metrics.json` (a licence note
/// or a Yahoo Finance source), joined to signals through the catalogue's
/// `metrics`. The built-in lists below are a floor, used even if those files
/// can't be read, so figures are never shown by accident.
public enum RestrictedData {
    /// Metrics restricted when the app was built (`RESTRICTED_*` and Yahoo
    /// sources in scripts/fetch_metrics.py).
    public static let knownMetrics: Set<String> = [
        "vix", "spx", "ftse", "move", "us10y", "dxy", "gold", "btc", "usdjpy",
        "brent", "ttf", "hy_oas", "epu", "gpr",
    ]

    /// Signals built on those metrics when the app was built, for when the
    /// catalogue isn't available.
    public static let knownSignals: Set<String> = [
        "equity-stress", "ftse", "bond-volatility", "credit-spreads", "dollar",
        "gold", "crypto", "yen-carry", "oil", "eu-gas",
    ]

    /// Metrics whose licence or source rules out republishing.
    public static func restrictedMetrics(in document: MetricsDocument?) -> Set<String> {
        var result = knownMetrics
        for (key, info) in document?.metrics ?? [:] {
            let terms = [info.licence, info.note].compactMap { $0 }.joined(separator: " ").lowercased()
            if terms.contains("not republished") || info.source == "Yahoo Finance" {
                result.insert(key)
            }
        }
        return result
    }

    /// Signals whose figures must be withheld.
    public static func restrictedSignals(catalogue: CatalogueDocument?, metrics: MetricsDocument?) -> Set<String> {
        let restricted = restrictedMetrics(in: metrics)
        var result = knownSignals
        for entry in catalogue?.signals ?? [] where !Set(entry.metrics ?? []).isDisjoint(with: restricted) {
            result.insert(entry.id)
        }
        return result
    }

    /// The signal with its figures removed.
    public static func withholding(_ signal: Signal) -> Signal {
        var copy = signal
        copy.value = nil
        copy.valueNum = nil
        copy.rubricHit = nil
        copy.basisDetail = nil
        copy.figuresWithheld = true
        return copy
    }
}
