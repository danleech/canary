import SwiftUI

/// Four tabs, like Health: Summary, Browse, Changes and Search.
///
/// When the window is regular in both directions (iPhone Duo open) the tab bar
/// becomes a sidebar, as Health's does there, and Browse's items are listed in
/// it directly, so every domain is one tap away. Standard containers only, so
/// iOS moves the bars where each device needs them — including iPhone Duo's
/// vertical bars — and handles the fold.
struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(BoardStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// iPhone Duo's inner display. A Pro Max in landscape is regular × compact
    /// and keeps the tab bar.
    private var usesSidebar: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }

    var body: some View {
        // Maps the selection for the current layout in the same pass that builds
        // the tabs, so it never points at a tab that isn't there while folding.
        let selection = Binding<AppTab>(
            get: { router.displayedTab(usesSidebar: usesSidebar) },
            set: { router.tab = $0 }
        )
        @Bindable var routing = router
        Group {
            if let board = store.board {
                // The tab set itself depends on the layout: iPhone shows every tab
                // it's given in its tab bar (overflowing into More), whatever their
                // sidebar or tab bar visibility says.
                TabView(selection: selection) {
                    Tab("Summary", systemImage: "gauge.with.dots.needle.50percent", value: AppTab.summary) {
                        SummaryView()
                    }
                    if !usesSidebar {
                        Tab("Browse", systemImage: "square.grid.2x2.fill", value: AppTab.browse) {
                            BrowseView()
                        }
                    }
                    Tab("Changes", systemImage: "clock.arrow.circlepath", value: AppTab.changes) {
                        ChangesView()
                    }
                    Tab(value: AppTab.search, role: .search) {
                        SearchView()
                    }
                    if usesSidebar {
                        TabSection("Browse") {
                            Tab("All Signals", systemImage: "list.bullet", value: AppTab.browseSection(.allSignals)) {
                                BrowseSectionView(selection: .allSignals)
                            }
                            Tab("Situations", systemImage: "point.3.connected.trianglepath.dotted",
                                value: AppTab.browseSection(.situations)) {
                                BrowseSectionView(selection: .situations)
                            }
                            ForEach(board.domains) { domain in
                                Tab(domain.name, systemImage: DomainStyle.symbol(for: domain.id),
                                    value: AppTab.browseSection(.domain(domain.id))) {
                                    BrowseSectionView(selection: .domain(domain.id))
                                }
                            }
                        }
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
                // On the tab view, so the Search tab implements it: in the tab bar
                // on iPhone, at the top of the sidebar on iPhone Duo's inner display.
                .searchable(text: $routing.searchQuery, prompt: "Signals, domains, situations")
                .modifier(TabBarPlacement(usesSidebar: usesSidebar))
                .onChange(of: usesSidebar, initial: true) { _, value in
                    router.adapt(usesSidebar: value)
                }
                .onChange(of: router.tab) { _, _ in
                    router.adapt(usesSidebar: usesSidebar)
                }
                #if DEBUG
                .modifier(DebugSheetPresenter())
                #endif
            } else {
                FirstLoadView()
            }
        }
    }
}

/// Opts into the sidebar on iPhone Duo's inner display (iOS 27). Without it,
/// iPhone keeps a bottom tab bar even at regular width.
private struct TabBarPlacement: ViewModifier {
    let usesSidebar: Bool

    func body(content: Content) -> some View {
        // SwiftUI 8 is the iOS 27 SDK (Xcode 27). Older Xcodes build without the sidebar.
        #if canImport(SwiftUI, _version: 8.0)
        if #available(iOS 27.0, *) {
            content.defaultTabBarPlacement(usesSidebar ? .sidebar : .automatic)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// A Browse item as its own sidebar destination, with its own navigation stack.
private struct BrowseSectionView: View {
    let selection: BrowseSelection
    @Environment(Router.self) private var router

    var body: some View {
        let path = Binding(
            get: { router.sectionPaths[selection] ?? [] },
            set: { router.sectionPaths[selection] = $0 }
        )
        NavigationStack(path: path) {
            Group {
                switch selection {
                case .allSignals: AllSignalsView()
                case .situations: SituationListView()
                case .domain(let id): DomainView(domainID: id)
                }
            }
            .routeDestinations()
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
