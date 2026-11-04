import SwiftUI

/// Two columns when there's room for both at a comfortable width — iPhone Duo's
/// inner display, beside its sidebar or not, or any iPhone in landscape — and
/// one column otherwise, so the single-column layout reflows instead of
/// stretching (HIG, *Designing for iPhone Duo*: Reflow). The choice is made
/// from the width actually available, in one layout pass, never from the
/// device model.
///
/// On iPhone Duo the gutter between the columns is placed on the hinge when it
/// falls between two usable columns, so no card is creased when the device is
/// folded like a book. The fold is not in the middle of the safe area (the
/// vertical bar takes one side), so its position comes from the display's
/// reserved regions rather than from halving the width.
struct AdaptiveColumns<Leading: View, Trailing: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var fold: ColumnSplit?

    var body: some View {
        ColumnsLayout(spacing: spacing, allowsColumns: !typeSize.isAccessibilitySize, fold: fold) {
            VStack(alignment: .leading, spacing: spacing) { leading }
            VStack(alignment: .leading, spacing: spacing) { trailing }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .modifier(FoldReader(fold: $fold))
    }
}

/// Where to split two columns: the leading width and the gutter after it.
struct ColumnSplit: Equatable {
    var leading: CGFloat
    var gutter: CGFloat
}

/// Places its first subview beside its second when both columns can be at least
/// `minColumnWidth` wide, and stacks them otherwise.
struct ColumnsLayout: Layout {
    var spacing: CGFloat
    var allowsColumns: Bool
    var fold: ColumnSplit?
    var minColumnWidth: CGFloat = 300

    private func split(for width: CGFloat) -> ColumnSplit? {
        guard allowsColumns, width >= minColumnWidth * 2 + spacing else { return nil }
        if let fold, fold.leading >= minColumnWidth, width - fold.leading - fold.gutter >= minColumnWidth {
            return fold
        }
        return ColumnSplit(leading: (width - spacing) / 2, gutter: spacing)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width
            ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max()
            ?? 0
        if subviews.count == 2, let split = split(for: width) {
            let leading = subviews[0].sizeThatFits(ProposedViewSize(width: split.leading, height: nil))
            let trailing = subviews[1].sizeThatFits(ProposedViewSize(width: width - split.leading - split.gutter, height: nil))
            return CGSize(width: width, height: max(leading.height, trailing.height))
        }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let gaps = heights.filter { $0 > 0 }.count
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(gaps - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if subviews.count == 2, let split = split(for: bounds.width) {
            subviews[0].place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: split.leading, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.minX + split.leading + split.gutter, y: bounds.minY),
                              anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width - split.leading - split.gutter, height: nil))
            return
        }
        var y = bounds.minY
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: nil))
            if size.height > 0 { y += size.height + spacing }
        }
    }
}

/// On iOS 27.1 or later, reads where the hinge falls across this view.
private struct FoldReader: ViewModifier {
    @Binding var fold: ColumnSplit?

    func body(content: Content) -> some View {
        // SwiftUI 8.0.85 is the iOS 27.1 SDK (Xcode 27.1), the first with reserved
        // regions. Older Xcodes build without fold-aware gutters.
        #if canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            content.onGeometryChange(for: ColumnSplit?.self) { proxy in
                Self.foldSplit(proxy)
            } action: { fold = $0 }
        } else {
            content
        }
        #else
        content
        #endif
    }

    #if canImport(SwiftUI, _version: 8.0.85)
    /// Uses the hinge's region, active or not, as the gutter. Its frame already
    /// includes the margins either side of the crease.
    @available(iOS 27.1, *)
    static func foldSplit(_ proxy: GeometryProxy) -> ColumnSplit? {
        let regions = proxy.reservedRegions(kind: .division, options: .includeInactive)
        // A vertical fold: taller than it is wide.
        guard let frame = regions.first(where: { $0.frame.height > $0.frame.width })?.frame else { return nil }
        let width = proxy.size.width
        guard frame.minX > 0, frame.maxX < width else { return nil }
        return ColumnSplit(leading: frame.minX, gutter: max(frame.width, 16))
    }
    #endif
}
