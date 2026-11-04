#if DEBUG
import SwiftUI
import WidgetKit

/// Debug only: every widget, at iPhone widget sizes, drawn by the same views the
/// widget extension uses, so CI can screenshot them (`-CanarySheet widgets`).
/// It shows the widgets' content; the Home Screen's own container and the Lock
/// Screen's tinting are approximated.
struct WidgetGalleryView: View {
    @Environment(BoardStore.self) private var store

    private let small = CGSize(width: 158, height: 158)
    private let medium = CGSize(width: 338, height: 158)
    private let large = CGSize(width: 338, height: 354)

    var body: some View {
        NavigationStack {
            ScrollView {
                if let board = store.board {
                    let pins = SharedSettings.pinnedIDs
                    let open = board.signals.first { $0.id == "earthquakes" } ?? board.signals[0]
                    let withheld = board.signals.first(where: \.withholdsFigures)
                    VStack(alignment: .leading, spacing: 22) {
                        section("World State")
                        HStack(alignment: .top, spacing: 16) {
                            frame("Small", small, world: board) {
                                WorldStateWidgetView(entry: WorldEntry(date: .now, board: board), family: .systemSmall)
                            }
                            lockScreen(board)
                        }
                        frame("Medium", medium, world: board) {
                            WorldStateWidgetView(entry: WorldEntry(date: .now, board: board), family: .systemMedium)
                        }
                        section("Signal (Canary+)")
                        HStack(alignment: .top, spacing: 16) {
                            frame(open.name, small) {
                                SignalWidgetView(entry: signalEntry(open, board), family: .systemSmall)
                            }
                            if let withheld {
                                frame("\(withheld.name), figures withheld", small) {
                                    SignalWidgetView(entry: signalEntry(withheld, board), family: .systemSmall)
                                }
                            }
                        }
                        frame("Without Canary+", small) {
                            SignalWidgetView(entry: SignalEntry(date: .now, signal: open, history: [], isPlus: false),
                                             family: .systemSmall)
                        }
                        section("Pinned (Canary+)")
                        frame("Medium", medium) {
                            PinnedWidgetView(entry: PinnedEntry(date: .now, board: board, pinnedIDs: pins, isPlus: true),
                                             family: .systemMedium)
                        }
                        frame("Large", large) {
                            PinnedWidgetView(entry: PinnedEntry(date: .now, board: board, pinnedIDs: pins, isPlus: true),
                                             family: .systemLarge)
                        }
                    }
                    .padding()
                }
            }
            .debugScrollable()
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Widgets")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func signalEntry(_ signal: Signal, _ board: Board) -> SignalEntry {
        SignalEntry(date: .now, signal: signal, history: board.history(for: signal.id), isPlus: true)
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.title3.bold())
    }

    /// A widget at its size on its background, with a label underneath.
    private func frame<Content: View>(_ label: String, _ size: CGSize, world: Board? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
                .padding(16)
                .frame(width: size.width, height: size.height)
                .background {
                    if let world {
                        BandMeshBackground(band: world.status.world.bandKind, base: Color(.systemBackground))
                    } else {
                        Color(.systemBackground)
                    }
                }
                .clipShape(.rect(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: size.width, alignment: .leading)
        }
    }

    /// The Lock Screen families on a dark wallpaper, roughly as iOS tints them.
    private func lockScreen(_ board: Board) -> some View {
        let entry = WorldEntry(date: .now, board: board)
        return VStack(alignment: .leading, spacing: 10) {
            WorldStateWidgetView(entry: entry, family: .accessoryInline)
                .font(.footnote)
            HStack(spacing: 10) {
                WorldStateWidgetView(entry: entry, family: .accessoryCircular)
                    .frame(width: 72, height: 72)
                WorldStateWidgetView(entry: entry, family: .accessoryRectangular)
                    .frame(width: 160, height: 72)
            }
            Text("Lock Screen")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(12)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .background(LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom),
                    in: .rect(cornerRadius: 22, style: .continuous))
    }
}
#endif
