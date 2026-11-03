import Foundation
import Observation
import StoreKit
import WidgetKit

/// Canary+ subscription state, from StoreKit 2.
@MainActor
@Observable
final class PlusStore {
    /// Product identifiers. Create matching auto-renewable subscriptions, in one
    /// subscription group, in App Store Connect. `Config/Canary.storekit` mirrors
    /// them for local testing.
    static let productIDs = [
        "com.danleech.canary.plus.yearly",
        "com.danleech.canary.plus.monthly",
    ]

    private(set) var isPlus: Bool = SharedSettings.isPlus
    private var updates: Task<Void, Never>?

    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refreshEntitlement()
            }
        }
        Task { await refreshEntitlement() }
    }

    /// Re-derives the entitlement from verified transactions.
    func refreshEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil {
                active = true
            }
        }
        setPlus(active)
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    private func setPlus(_ value: Bool) {
        guard value != isPlus || value != SharedSettings.isPlus else { return }
        isPlus = value
        SharedSettings.isPlus = value
        if !value { SharedSettings.alertsEnabled = false }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
