import SwiftUI

/// A segmented bar that lights up with how loud a channel currently is.
struct LevelMeter: View {
    let level: Float
    var segments = 8
    var segmentWidth: CGFloat = 3
    var height: CGFloat = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                Capsule()
                    .fill(fill(for: index))
                    .frame(width: segmentWidth)
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.08), value: level)
        .accessibilityHidden(true)
    }

    private func fill(for index: Int) -> AnyShapeStyle {
        let fraction = Float(index + 1) / Float(segments)
        guard fraction <= level else { return AnyShapeStyle(.quaternary) }
        if fraction > 0.9 { return AnyShapeStyle(Color.red) }
        if fraction > 0.7 { return AnyShapeStyle(Color.orange) }
        return AnyShapeStyle(Color.green)
    }
}

/// One labelled channel of the recording meter: mic or system audio.
struct ChannelMeter: View {
    let symbol: String
    let name: String
    let level: Float
    let isSilent: Bool
    var segments = 8

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isSilent ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                .frame(width: 11)
            LevelMeter(level: level, segments: segments)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(isSilent ? "no sound" : "\(Int((level * 100).rounded())) percent")
    }
}
