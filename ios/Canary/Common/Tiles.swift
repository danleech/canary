import SwiftUI

// Health-style tiles: rounded cards on the grouped background, each with a soft
// wash of its category's colour, a coloured header, and a chart where the data
// suits one.

/// A rounded tile with an optional pastel wash in a domain or level colour.
struct TileBackground: ViewModifier {
    var tint: Color?
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay {
                        if let tint {
                            shape.fill(LinearGradient(
                                colors: [tint.opacity(0.17), tint.opacity(0.05), .clear],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                        }
                    }
            }
            .contentShape(shape)
    }
}

extension View {
    /// A Health-style tile, washed with `tint`.
    func tile(tint: Color? = nil, padding: CGFloat = 16) -> some View {
        modifier(TileBackground(tint: tint, padding: padding))
    }
}

/// The header of a tile, as in Health: a symbol and title in the category's
/// colour, then the time and a chevron on the trailing side.
struct TileHeader: View {
    let title: String
    let systemImage: String
    let hue: Hue
    var detail: String? = nil
    var showsChevron = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(hue.fill)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(hue.text)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// A rounded-square icon with a gradient fill, like Settings and Shortcuts.
struct IconBadge: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Alert, Watch and Normal as one rounded bar, each part in proportion.
struct LevelBar: View {
    let counts: [Level: Int]
    var height: CGFloat = 8

    var body: some View {
        let levels = [Level.alert, .watch, .normal].filter { counts[$0, default: 0] > 0 }
        let total = max(levels.map { counts[$0, default: 0] }.reduce(0, +), 1)
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(levels, id: \.self) { level in
                    Capsule()
                        .fill(level.color.gradient)
                        .frame(width: max((proxy.size.width - CGFloat(levels.count - 1) * 2)
                                          * CGFloat(counts[level, default: 0]) / CGFloat(total), height))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A count with its level's symbol on Liquid Glass, for the World State hero.
struct GlassCountChip: View {
    let level: Level
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            StatusGlyph(level, font: .footnote)
            Text("\(count)")
                .font(.subheadline.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
            Text(level.label)
                .font(.footnote.weight(.medium))
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(level.label)")
    }
}

/// A page background: the grouped background with a soft wash of colour at the
/// top, as Health and Fitness pages have.
struct WashedBackground: View {
    let tint: Color

    var body: some View {
        Color(.systemGroupedBackground)
            .overlay(alignment: .top) {
                LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.06), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 420)
            }
            .ignoresSafeArea()
    }
}
