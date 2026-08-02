import SwiftUI

/// Hairline score sparkline in the editorial register: a single lane-blue
/// polyline with a terminal dot, riding on a baseline hairline. No axes,
/// no fill — the number row beneath it carries the labels.
struct Sparkline: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geo in
            let pts = Self.points(for: values, in: geo.size)
            ZStack {
                if pts.count > 1 {
                    Path { p in p.addLines(pts) }
                        .stroke(DS.accent, style: StrokeStyle(
                            lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
                if let last = pts.last {
                    Circle()
                        .fill(DS.accent)
                        .frame(width: 6, height: 6)
                        .position(last)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.border).frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    /// Normalized plot points (top-left origin), with 15% vertical headroom
    /// so the line never kisses the frame. Pure — unit-tested.
    static func points(for values: [Int], in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let lo = values.min() ?? 0
        let hi = values.max() ?? 0
        let span = CGFloat(max(hi - lo, 1))
        return values.enumerated().map { i, v in
            let x = values.count > 1
                ? CGFloat(i) * size.width / CGFloat(values.count - 1)
                : size.width / 2
            let t = CGFloat(v - lo) / span
            let y = size.height * (1 - (0.15 + 0.70 * t))
            return CGPoint(x: x, y: y)
        }
    }
}
