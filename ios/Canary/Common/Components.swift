import SafariServices
import SwiftUI

// MARK: - Cards

/// Health-style rounded card on the grouped background.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardBackground(padding: padding)) }
}

/// A tile's heading, as Health heads its cards: a symbol in the tile's colour
/// and a short title.
struct ModuleHeader: View {
    let title: LocalizedStringKey
    let systemImage: String
    var hue: Hue? = nil
    @Environment(\.pageHue) private var pageHue

    init(_ title: LocalizedStringKey, systemImage: String, hue: Hue? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.hue = hue
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle((hue ?? pageHue)?.fill ?? Color.accentColor)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle((hue ?? pageHue)?.text ?? Color.primary)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Health-style section title with an optional trailing action, e.g. "Pinned … Edit".
struct SectionTitle<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
                .font(.body)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

extension EnvironmentValues {
    /// The colour of the page's domain, for its tiles' headings.
    @Entry var pageHue: Hue? = nil
}

extension View {
    /// In debug builds, honours `-CanaryScroll` for screenshots of long pages.
    @ViewBuilder func debugScrollable() -> some View {
        #if DEBUG
        modifier(DebugScroll())
        #else
        self
        #endif
    }
}

// MARK: - Navigation

/// The destination for every `Route`, shared by all tabs.
struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .signal(let id): SignalDetailView(signalID: id)
        case .situation(let id): SituationDetailView(situationID: id)
        case .domain(let id): DomainView(domainID: id)
        case .world: WorldStateDetailView()
        case .situations: SituationListView()
        case .allSignals: AllSignalsView()
        case .level(let level): LevelListView(level: level)
        }
    }
}

extension View {
    /// Registers `RouteDestination` for a navigation stack.
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { RouteDestination(route: $0) }
    }
}

// MARK: - Title

/// The App Store and Music pattern: a page's own large header carries its name,
/// and the name fades into the navigation bar only once that header has
/// scrolled away, so it's never shown twice.
struct ScrollRevealedTitle: ViewModifier {
    let title: String
    var threshold: CGFloat = 100
    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > threshold
            } action: { _, isPast in
                withAnimation(.easeInOut(duration: 0.2)) { isShown = isPast }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(isShown ? 1 : 0)
                        .accessibilityHidden(!isShown)
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }
}

extension View {
    func scrollRevealedTitle(_ title: String, threshold: CGFloat = 100) -> some View {
        modifier(ScrollRevealedTitle(title: title, threshold: threshold))
    }
}

// MARK: - Settings button

/// Opens Settings from any tab's toolbar.
struct SettingsToolbarItem: ToolbarContent {
    @Binding var isPresented: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isPresented = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

// MARK: - Safari

/// In-app Safari for source links, like News.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

private struct WebPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Opens web links in in-app Safari for a view subtree.
struct InAppSafari: ViewModifier {
    @State private var page: WebPage?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "https" || url.scheme == "http" else { return .systemAction }
                page = WebPage(url: url)
                return .handled
            })
            .sheet(item: $page) { page in
                SafariView(url: page.url).ignoresSafeArea()
            }
    }
}

extension View {
    func opensLinksInApp() -> some View { modifier(InAppSafari()) }
}

// MARK: - Refresh status

/// "Updated 18:02 · Next check about 23:40", or a stale warning.
struct BoardFreshnessText: View {
    @Environment(BoardStore.self) private var store

    var body: some View {
        if let board = store.board {
            let now = store.now
            Group {
                if board.isStale(at: now) {
                    Label("The board hasn't updated since \(CanaryFormat.when(board.status.asOf, now: now)). Statuses may be out of date.",
                          systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                } else if let next = board.status.nextRun, next > now {
                    Text("Updated \(CanaryFormat.when(board.status.asOf, now: now)) · Next check about \(next.formatted(date: .omitted, time: .shortened))")
                } else {
                    Text("Updated \(CanaryFormat.when(board.status.asOf, now: now))")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}
