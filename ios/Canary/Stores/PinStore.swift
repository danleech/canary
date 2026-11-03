import Foundation
import Observation
import SwiftUI
import WidgetKit

/// The signals a person has pinned to Summary, like Health's Pinned or a Stocks watchlist.
@MainActor
@Observable
final class PinStore {
    private(set) var ids: [String] = SharedSettings.pinnedIDs

    func isPinned(_ id: String) -> Bool { ids.contains(id) }

    /// Whether another pin is allowed on the current plan.
    func canPin(isPlus: Bool) -> Bool {
        isPlus || ids.count < PlusFeature.freePinLimit
    }

    func pin(_ id: String) {
        guard !ids.contains(id) else { return }
        ids.append(id)
        save()
    }

    func unpin(_ id: String) {
        ids.removeAll { $0 == id }
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        ids.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        ids.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        SharedSettings.pinnedIDs = ids
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.pinned)
    }
}
