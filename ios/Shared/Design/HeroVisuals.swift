import SwiftUI

// The World State's visuals, shared by the app and its widgets.

/// An Activity-style ring for the World State score out of 100.
struct ScoreRing: View {
    let score: Int?
    let band: WorldBand
    var lineWidth: CGFloat = 14

    var body: some View {
        let fraction = CGFloat(min(max(score ?? 0, 0), 100)) / 100
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(fraction, 0.001))
                .stroke(
                    AngularGradient(colors: band.ringColors, center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360 * Double(fraction))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: band.color.opacity(0.25), radius: 4, y: 2)
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

/// Weather-style pastel mesh gradient in the World State band's colours.
struct BandMeshBackground: View {
    let band: WorldBand
    var base: Color = Color(.secondarySystemGroupedBackground)

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.62, 0.42], [1, 0.5],
                [0, 1], [0.45, 1], [1, 1],
            ],
            colors: band.meshColors
        )
        .background(base)
    }
}

