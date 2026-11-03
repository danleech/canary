import SwiftUI

// Colour means attention level and nothing else, so domains never get status
// colours. Every level also has its own shape and label: colour is never the
// only cue (charter §6). Shapes match the website's legend.

extension Level {
    public var color: Color {
        switch self {
        case .alert: .red
        case .watch: .orange
        case .normal: .green
        case .stale, .pending: .gray
        }
    }

    /// Fill and text for filled badges, chosen for WCAG AA text contrast:
    /// dark text on green and orange, white text on a deepened red or grey.
    public var pillFill: Color {
        switch self {
        case .alert: Color.red.mix(with: .black, by: 0.25)
        case .watch: .orange
        case .normal: .green
        case .stale, .pending: Color.gray.mix(with: .black, by: 0.35)
        }
    }

    public var pillText: Color {
        switch self {
        case .watch, .normal: .black
        case .alert, .stale, .pending: .white
        }
    }

    /// Distinct silhouettes: octagon, triangle, circle, dashed circle.
    public var symbol: String {
        switch self {
        case .alert: "exclamationmark.octagon.fill"
        case .watch: "exclamationmark.triangle.fill"
        case .normal: "checkmark.circle.fill"
        case .stale, .pending: "circle.dashed"
        }
    }
}

extension WorldBand {
    public var color: Color {
        switch self {
        case .calm: .green
        case .unsettled: .yellow
        case .strained: .orange
        case .severe: .red
        case .unknown: .gray
        }
    }
}

/// SF Symbols for domains, shown in the accent colour so they never read as a status.
public enum DomainStyle {
    public static func symbol(for id: String) -> String {
        switch id {
        case "markets": "chart.line.uptrend.xyaxis"
        case "economy": "building.columns.fill"
        case "energy": "fuelpump.fill"
        case "geopolitics": "globe.europe.africa.fill"
        case "conflict": "shield.lefthalf.filled"
        case "hazards": "hurricane"
        case "climate": "thermometer.sun.fill"
        case "health": "cross.case.fill"
        case "tech": "network"
        case "humanitarian": "person.3.fill"
        case "uk": "binoculars.fill"
        default: "circle.grid.2x2.fill"
        }
    }
}

// MARK: - Status views

/// The level's symbol in its colour. Hidden from VoiceOver: pair it with text.
public struct StatusGlyph: View {
    let level: Level
    var font: Font = .body

    public init(_ level: Level, font: Font = .body) {
        self.level = level
        self.font = font
    }

    public var body: some View {
        Group {
            switch level {
            case .stale, .pending:
                // A single-layer symbol: one colour.
                Image(systemName: level.symbol)
                    .foregroundStyle(level.color)
            default:
                Image(systemName: level.symbol)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(level == .watch ? Color.black.opacity(0.85) : Color.white, level.color)
            }
        }
        .font(font)
        .accessibilityHidden(true)
    }
}

/// Stocks-style filled capsule with the level's name, e.g. "Watch".
public struct StatusPill: View {
    let level: Level
    var compact = false

    public init(_ level: Level, compact: Bool = false) {
        self.level = level
        self.compact = compact
    }

    public var body: some View {
        Text(level.label)
            .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(level.pillText)
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, compact ? 2 : 4)
            .frame(minWidth: compact ? 56 : 72)
            .background(level.pillFill, in: .rect(cornerRadius: compact ? 6 : 8, style: .continuous))
    }
}

/// Glyph plus label, e.g. "▲ Watch", for headers and lists.
public struct StatusLabel: View {
    let level: Level
    var font: Font = .subheadline.weight(.semibold)

    public init(_ level: Level, font: Font = .subheadline.weight(.semibold)) {
        self.level = level
        self.font = font
    }

    public var body: some View {
        Label {
            Text(level.label)
        } icon: {
            StatusGlyph(level, font: font)
        }
        .font(font)
        .foregroundStyle(level.color)
    }
}

/// Weather-style gradient bar for the World State index with a marker at the score.
public struct WorldGaugeBar: View {
    let score: Int?
    var height: CGFloat = 6

    public init(score: Int?, height: CGFloat = 6) {
        self.score = score
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            let fraction = CGFloat(min(max(score ?? 0, 0), 100)) / 100
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(
                        stops: [
                            .init(color: .green, location: 0),
                            .init(color: .green, location: 0.2),
                            .init(color: .yellow, location: 0.35),
                            .init(color: .orange, location: 0.5),
                            .init(color: .red, location: 0.75),
                            .init(color: .red, location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing))
                if score != nil {
                    Circle()
                        .fill(.white)
                        .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                        .frame(width: height + 4, height: height + 4)
                        .offset(x: fraction * (proxy.size.width - height - 4))
                }
            }
            .frame(height: height + 4)
            .frame(maxHeight: .infinity)
        }
        .frame(height: height + 4)
        .accessibilityHidden(true)
    }
}

// MARK: - Accessibility text

extension Signal {
    /// One sentence for VoiceOver: name, level, trend and value.
    public func accessibilitySummary(at now: Date = .now) -> String {
        var parts = [name, level(at: now).label]
        if let trend, trend != .unknown { parts.append(trend.label) }
        if let value { parts.append(value) }
        return parts.joined(separator: ", ")
    }
}
