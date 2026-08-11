import SwiftUI

/// The About screen's action chip: a tracked all-caps verb inside a hairline
/// outline of its own tint.
///
/// Deliberately **not** a `VerdictChip`, though the two are cousins to look at.
/// That mark means "we measured this and here is the answer", and its own note
/// makes the converse a rule — anything the app did not measure must not wear
/// one. These are verbs the user can press: prepare an export, erase sessions,
/// drop footage. A finding and a button should not be the same mark.
///
/// What they do share is the chip's **capped growth**. `.font(.custom(_:size:))`
/// is fixed type that ignores Dynamic Type outright, so every control on this
/// screen used to stay at 10pt while the prose beside it grew to accessibility
/// sizes. Scaling relative to `.caption2` with a ceiling fixes that without
/// letting a long tracked verb — PREPARE CSV SPREADSHEET is 23 characters —
/// run past the column it sits in.
struct DataActionLabel: View {
    /// What rides ahead of the verb: a symbol, or a spinner while the action
    /// this chip names is already running.
    enum Adornment: Equatable {
        case icon(String)
        case spinner
    }

    let title: String
    let adornment: Adornment
    let tint: Color

    /// 10pt at the default text size — what every chip on this screen already
    /// used, so adopting this changes no pixels at the default size.
    static let baseSize: CGFloat = 10
    /// Growth stops here, the same ~1.4× ceiling `VerdictChip` draws at 13/9.
    /// Past it the label wraps to a second line and the pill grows taller,
    /// which is legible; unbounded growth is not.
    static let maxSize: CGFloat = 14

    @ScaledMetric(relativeTo: .caption2) private var scaled: CGFloat = DataActionLabel.baseSize

    /// Type size after the cap, and the factor the geometry rides on so the
    /// outline keeps its proportions instead of strangling the label.
    private var size: CGFloat { min(scaled, Self.maxSize) }
    private var growth: CGFloat { size / Self.baseSize }

    var body: some View {
        HStack(spacing: 6 * growth) {
            switch adornment {
            case let .icon(name):
                Image(systemName: name)
                    .font(.caption)
                    .accessibilityHidden(true)
            case .spinner:
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.custom(GroteskWeight.medium.postScriptName, size: size))
                .tracking(1.2)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10 * growth)
        .padding(.vertical, 8 * growth)
        .overlay(RoundedRectangle(cornerRadius: 6 * growth)
            .stroke(tint.opacity(0.45), lineWidth: 1))
        // Pill stays visually compact; the frame extends the tap target
        // to the HIG 44pt minimum.
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
