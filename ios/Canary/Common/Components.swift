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
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardBackground(padding: padding)) }
}

/// Weather-style module caption: small symbol and uppercase title in grey.
struct ModuleHeader: View {
    let title: LocalizedStringKey
    let systemImage: String

    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
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

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Opens web links in in-app Safari for a view subtree.
struct InAppSafari: ViewModifier {
    @State private var url: URL?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "https" || url.scheme == "http" else { return .systemAction }
                self.url = url
                return .handled
            })
            .sheet(item: $url) { url in
                SafariView(url: url).ignoresSafeArea()
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
