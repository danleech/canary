import SwiftUI

/// Choose and order pinned signals, like editing Health's Pinned list.
struct PinEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BoardStore.self) private var store
    @Environment(PinStore.self) private var pins
    @Environment(PlusStore.self) private var plus
    @State private var query = ""
    @State private var showsPaywall = false

    var body: some View {
        NavigationStack {
            if let board = store.board {
                List {
                    if query.isEmpty, !pins.ids.isEmpty {
                        Section {
                            ForEach(pins.ids, id: \.self) { id in
                                if let signal = board.signal(id) {
                                    pinnedRow(signal)
                                }
                            }
                            .onMove { pins.move(fromOffsets: $0, toOffset: $1) }
                            .onDelete { pins.remove(atOffsets: $0) }
                        } header: {
                            Text("Pinned")
                        } footer: {
                            if !plus.isPlus {
                                Text("You can pin \(PlusFeature.freePinLimit) signals. Canary+ removes the limit.")
                            }
                        }
                    }
                    ForEach(board.domains) { domain in
                        let signals = board.signals(inDomain: domain.id, at: store.now)
                            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
                        if !signals.isEmpty {
                            Section(domain.name) {
                                ForEach(signals) { signal in toggleRow(signal) }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $query, prompt: "Find a signal")
                .navigationTitle("Pinned Signals")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if query.isEmpty, pins.ids.count > 1 {
                        ToolbarItem(placement: .topBarLeading) { EditButton() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .sheet(isPresented: $showsPaywall) { CanaryPlusView(reason: .pins) }
            }
        }
    }

    private func pinnedRow(_ signal: Signal) -> some View {
        HStack(spacing: 12) {
            StatusGlyph(signal.level(at: store.now))
            Text(signal.name)
        }
        .accessibilityElement(children: .combine)
    }

    private func toggleRow(_ signal: Signal) -> some View {
        let pinned = pins.isPinned(signal.id)
        return Button {
            if pinned {
                pins.unpin(signal.id)
            } else if pins.canPin(isPlus: plus.isPlus) {
                pins.pin(signal.id)
            } else {
                showsPaywall = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: pinned ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(pinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
                Text(signal.name)
                    .foregroundStyle(.primary)
                Spacer()
                StatusGlyph(signal.level(at: store.now))
            }
            .contentShape(.rect)
        }
        .accessibilityLabel(signal.name)
        .accessibilityValue(pinned ? "Pinned" : "Not pinned")
        .accessibilityAddTraits(pinned ? .isSelected : [])
    }
}
