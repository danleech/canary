import SwiftUI

/// One column at compact width. Two columns at regular width — iPhone Duo's
/// inner display, or a Pro Max in landscape — so the single-column layout
/// reflows instead of stretching (HIG, *Designing for iPhone Duo*: Reflow).
///
/// On iPhone Duo the gutter between the columns is placed on the hinge, so no
/// card is creased when the device is folded like a book. The fold is not in
/// the middle of the safe area (the vertical bar takes one side), so the split
/// comes from the display's reserved regions rather than from halving the width.
struct AdaptiveColumns<Leading: View, Trailing: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if horizontalSizeClass == .regular, !typeSize.isAccessibilitySize {
            TwoColumns(spacing: spacing) { leading } trailing: { trailing }
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                leading
                trailing
            }
        }
    }
}

/// Where to split two columns: the leading width and the gutter after it.
struct ColumnSplit: Equatable {
    var leading: CGFloat
    var gutter: CGFloat
}

private struct TwoColumns<Leading: View, Trailing: View>: View {
    let spacing: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @State private var split: ColumnSplit?

    var body: some View {
        Group {
            if let split {
                HStack(alignment: .top, spacing: 0) {
                    column { leading }
                        .frame(width: split.leading)
                    Color.clear
                        .frame(width: split.gutter, height: 1)
                        .accessibilityHidden(true)
                    column { trailing }
                        .frame(maxWidth: .infinity)
                }
            } else {
                HStack(alignment: .top, spacing: spacing) {
                    column { leading }
                    column { trailing }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FoldReader(spacing: spacing, split: $split))
    }

    private func column<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: spacing) { content() }
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Reads the container's width and, on iOS 27.1 or later, the vertical fold.
private struct FoldReader: ViewModifier {
    let spacing: CGFloat
    @Binding var split: ColumnSplit?

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onGeometryChange(for: ColumnSplit.self) { proxy in
                Self.foldSplit(proxy, spacing: spacing) ?? Self.evenSplit(proxy.size.width, spacing: spacing)
            } action: { split = $0 }
        } else {
            content.onGeometryChange(for: ColumnSplit.self) { proxy in
                Self.evenSplit(proxy.size.width, spacing: spacing)
            } action: { split = $0 }
        }
    }

    static func evenSplit(_ width: CGFloat, spacing: CGFloat) -> ColumnSplit {
        ColumnSplit(leading: max((width - spacing) / 2, 0), gutter: spacing)
    }

    /// Uses the hinge's region, active or not, as the gutter. Its frame already
    /// includes the margins either side of the crease.
    @available(iOS 27.1, *)
    static func foldSplit(_ proxy: GeometryProxy, spacing: CGFloat) -> ColumnSplit? {
        let regions = proxy.reservedRegions(kind: .division, options: .includeInactive)
        guard let fold = regions.first(where: { $0.frame.height > $0.frame.width })?.frame else { return nil }
        let width = proxy.size.width
        // Only use the fold when both sides keep a sensible column.
        guard fold.minX > width * 0.3, fold.maxX < width * 0.7 else { return nil }
        return ColumnSplit(leading: fold.minX, gutter: max(fold.width, spacing))
    }
}
