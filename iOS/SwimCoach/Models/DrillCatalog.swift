import Foundation

/// A practice drill in the library. Static coaching content — every issue
/// the model can detect maps to at least one drill (enforced by tests).
struct Drill: Identifiable, Hashable {
    let id: String            // stable kebab-case slug
    let name: String
    let focus: DrillFocus
    let fixes: [String]       // FeedbackEngine issue names this drill targets
    let goal: String          // one line: what it trains
    let steps: [String]
    let dose: String          // suggested set, e.g. "4 × 25 m"
}

enum DrillFocus: String, CaseIterable {
    case arms = "Arms & catch"
    case body = "Body line"
    case kick = "Kick & timing"
}

enum DrillCatalog {

    static let all: [Drill] = [
        // ── Arms & catch ─────────────────────────────────────────────────
        Drill(
            id: "fingertip-drag",
            name: "Fingertip Drag",
            focus: .arms,
            fixes: ["left_elbow_overextension", "right_elbow_overextension"],
            goal: "Relaxed, high-elbow recovery and a soft entry in front of the shoulder.",
            steps: [
                "Swim freestyle at easy effort.",
                "On every recovery, drag your fingertips along the water surface.",
                "Keep the elbow the highest point of the arm until the hand passes your head.",
                "Let the hand enter fingertips-first, in line with your shoulder.",
            ],
            dose: "4 × 25 m, full rest"),
        Drill(
            id: "catch-up",
            name: "Catch-Up Drill",
            focus: .arms,
            fixes: ["stroke_asymmetry", "left_elbow_overextension", "right_elbow_overextension"],
            goal: "Even timing between sides and a full front-quadrant extension.",
            steps: [
                "Push off in streamline, both arms extended.",
                "Pull with one arm only; the other stays pointed at the far wall.",
                "The recovering hand must touch the waiting hand before the next pull starts.",
                "Keep your lead arm just under the surface — not pressing down.",
            ],
            dose: "6 × 25 m, alternating lead"),
        Drill(
            id: "fist-drill",
            name: "Fist Drill",
            focus: .arms,
            fixes: ["left_elbow_collapse", "right_elbow_collapse"],
            goal: "A high-elbow catch that presses water back with the forearm, not the palm.",
            steps: [
                "Swim freestyle with both hands closed into loose fists.",
                "Feel for pressure on your forearm during each pull.",
                "Keep the elbow high and wide — point it at the lane rope, not the floor.",
                "Open the hands for the last lap and keep the same forearm pressure.",
            ],
            dose: "4 × 50 m (25 fist / 25 swim)"),
        Drill(
            id: "single-arm",
            name: "Single-Arm Freestyle",
            focus: .arms,
            fixes: ["stroke_asymmetry", "left_elbow_collapse", "right_elbow_collapse"],
            goal: "Isolates each side so the weaker pull can't hide behind the stronger one.",
            steps: [
                "Keep one arm extended in front; stroke with the other only.",
                "Breathe toward the stroking side, rotating from the hips.",
                "Focus on a clean catch: fingertips down, elbow high.",
                "Swap arms each length; note which side feels weaker.",
            ],
            dose: "4 × 50 m (25 m each arm)"),

        // ── Body line ────────────────────────────────────────────────────
        Drill(
            id: "superman-glide",
            name: "Superman Glide",
            focus: .body,
            fixes: ["body_sag"],
            goal: "Finding the downhill body position — chest pressed, hips at the surface.",
            steps: [
                "Push off gently, arms extended, face down, legs still.",
                "Press your chest down an inch and feel your hips rise.",
                "Hold the glide until you slow, then stand and reset.",
                "Add a light flutter kick once the hips stay high on their own.",
            ],
            dose: "6 glides, then 2 × 25 m easy swim"),
        Drill(
            id: "six-kick-switch",
            name: "6-Kick Switch",
            focus: .body,
            fixes: ["body_sag", "low_kick_rate"],
            goal: "Connects kick rhythm to rotation while holding a tall, level body line.",
            steps: [
                "Kick six times on one side, bottom arm extended, top arm on your hip.",
                "Keep your head still and hips at the surface.",
                "Take one full stroke to rotate to the other side.",
                "Repeat: six kicks, switch, six kicks.",
            ],
            dose: "4 × 50 m with fins optional"),

        // ── Kick & timing ────────────────────────────────────────────────
        Drill(
            id: "vertical-kick",
            name: "Vertical Kicking",
            focus: .kick,
            fixes: ["left_knee_overbend", "right_knee_overbend"],
            goal: "A compact, hip-driven flutter kick — knees soft, not bicycling.",
            steps: [
                "In deep water, kick upright with arms crossed on your chest.",
                "Kick from the hips with long legs and floppy ankles.",
                "If your knees break forward, you'll sink — soften and lengthen.",
                "Rest as needed; quality beats duration.",
            ],
            dose: "4 × 30 s, 30 s rest"),
        Drill(
            id: "side-flutter",
            name: "Flutter Kick on Side",
            focus: .kick,
            fixes: ["left_knee_overbend", "right_knee_overbend", "low_kick_rate"],
            goal: "A steady, narrow kick that supports rotation instead of fighting it.",
            steps: [
                "Kick on your side, bottom arm extended, ear on shoulder.",
                "Keep the kick inside the shadow of your body — small and quick.",
                "Toes pointed, ankles loose, knees nearly straight.",
                "Swap sides each length.",
            ],
            dose: "4 × 25 m each side"),
        Drill(
            id: "two-beat-timing",
            name: "2-Beat Timing",
            focus: .kick,
            fixes: ["low_kick_rate"],
            goal: "One crisp kick per arm stroke — the minimum rhythm that keeps hips rotating.",
            steps: [
                "Swim slow freestyle and kick exactly once per arm pull.",
                "Snap the opposite-side leg as each hand enters the water.",
                "Feel the kick drive your hip rotation, not just your feet.",
                "Build to normal speed while keeping the 1:1 rhythm.",
            ],
            dose: "4 × 50 m easy"),
        Drill(
            id: "pull-buoy-pull",
            name: "Pull-Buoy Pull",
            focus: .kick,
            fixes: ["excessive_kick_rate"],
            goal: "Retrains an over-busy kick by removing it — propulsion from the pull alone.",
            steps: [
                "Place a pull buoy between your thighs and swim without kicking.",
                "Keep your legs quiet and let the buoy hold your hips up.",
                "Focus on long strokes and steady exhale.",
                "Afterwards, swim normally with a calm 2- or 6-beat kick.",
            ],
            dose: "4 × 50 m pull, 2 × 25 m swim"),
    ]

    /// Drills targeting a detected issue, in catalog order.
    static func drills(fixing issueName: String) -> [Drill] {
        all.filter { $0.fixes.contains(issueName) }
    }
}
