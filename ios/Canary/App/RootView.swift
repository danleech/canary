import SwiftUI

/// Four tabs, like Health: Summary, Browse, Changes and Search.
/// Standard containers only, so iOS moves the bars where each device needs
/// them — including iPhone Duo's vertical bars — and handles the fold.
struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(BoardStore.self) private var store

    var body: some View {
        @Bindable var router = router
        Group {
            if store.board == nil {
                FirstLoadView()
            } else {
                TabView(selection: $router.tab) {
                    Tab("Summary", systemImage: "gauge.with.dots.needle.50percent", value: AppTab.summary) {
                        SummaryView()
                    }
                    Tab("Browse", systemImage: "square.grid.2x2.fill", value: AppTab.browse) {
                        BrowseView()
                    }
                    Tab("Changes", systemImage: "clock.arrow.circlepath", value: AppTab.changes) {
                        ChangesView()
                    }
                    Tab(value: AppTab.search, role: .search) {
                        SearchView()
                    }
                }
                #if DEBUG
                .modifier(DebugSheetPresenter())
                #endif
            }
        }
    }
}

/// Shown only on the very first launch, before any copy of the board is saved.
private struct FirstLoadView: View {
    @Environment(BoardStore.self) private var store

    var body: some View {
        Group {
            if let message = store.errorMessage {
                ContentUnavailableView {
                    Label("Can't Load the Board", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await store.refresh() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading the board…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
