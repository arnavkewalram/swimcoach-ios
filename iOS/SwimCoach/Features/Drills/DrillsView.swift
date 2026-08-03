import SwiftUI
import SwiftData

/// The drill library: editorial index cards grouped by focus area. When
/// opened from an issue row, the drills that fix that issue are outlined
/// in lane blue and scrolled into view.
struct DrillsView: View {
    /// FeedbackEngine issue name to spotlight, if arriving from Results.
    var highlightIssue: String? = nil
    @Environment(\.modelContext) private var modelContext
    @Query private var practiceEvents: [DrillPracticeEvent]

    private var highlightedIDs: Set<String> {
        guard let issue = highlightIssue else { return [] }
        return Set(DrillCatalog.drills(fixing: issue).map(\.id))
    }

    /// Of the fixing drills, the one most due for practice — the scroll
    /// target and START HERE card.
    private var startHereID: String? {
        guard let issue = highlightIssue else { return nil }
        return DrillPractice.leastRecentlyPracticed(
            of: DrillCatalog.drills(fixing: issue).map(\.id),
            events: practiceEvents)
    }

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Every fault the analysis can detect maps to a drill here. Fold two or three into each warm-up.")
                            .font(.footnote)
                            .lineSpacing(3)
                            .foregroundStyle(DS.inkSecondary)
                            .padding(.top, 8)

                        ForEach(DrillFocus.allCases, id: \.self) { focus in
                            let drills = DrillCatalog.all.filter { $0.focus == focus }
                            SectionHeader(title: focus.rawValue)
                                .padding(.top, 6)
                            ForEach(drills) { drill in
                                DrillCard(
                                    number: cardNumber(of: drill),
                                    drill: drill,
                                    isHighlighted: highlightedIDs.contains(drill.id),
                                    isStartHere: drill.id == startHereID,
                                    practice: DrillPractice.summary(
                                        for: drill.id, events: practiceEvents),
                                    onMarkDone: {
                                        modelContext.insert(
                                            DrillPracticeEvent(drillID: drill.id))
                                        Haptics.tap()
                                    })
                                    .id(drill.id)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
                .onAppear {
                    if let target = startHereID
                        ?? DrillCatalog.all.first(where: { highlightedIDs.contains($0.id) })?.id {
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                    }
                }
            }
        }
        .navigationTitle("Drills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Drills")
                    .font(.grotesk(17, .medium))
                    .foregroundStyle(DS.ink)
            }
        }
        .toolbarBackground(DS.background, for: .navigationBar)
    }

    private func cardNumber(of drill: Drill) -> String {
        let idx = (DrillCatalog.all.firstIndex(of: drill) ?? 0) + 1
        return String(format: "%02d", idx)
    }
}

// MARK: - Drill index card

private struct DrillCard: View {
    let number: String
    let drill: Drill
    let isHighlighted: Bool
    var isStartHere: Bool = false
    let practice: DrillPractice.Summary
    let onMarkDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number)
                    .font(.grotesk(13, .bold))
                    .foregroundStyle(isHighlighted ? DS.accent : DS.inkTertiary)
                Text(drill.name)
                    .font(.grotesk(17, .bold))
                    .foregroundStyle(DS.ink)
                if isStartHere {
                    Text("START HERE")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 8))
                        .tracking(1.2)
                        .foregroundStyle(DS.onAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(DS.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .fixedSize()
                }
                Spacer()
                Text(drill.dose.uppercased())
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                    .tracking(0.8)
                    .foregroundStyle(DS.inkSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(DS.border, lineWidth: 1))
            }

            Text(drill.goal)
                .font(.footnote)
                .lineSpacing(3)
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(drill.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)")
                            .font(.grotesk(11, .bold))
                            .foregroundStyle(DS.accent)
                            .frame(width: 14, alignment: .trailing)
                            .padding(.top, 1)
                        Text(step)
                            .font(.footnote)
                            .lineSpacing(2)
                            .foregroundStyle(DS.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                    if i < drill.steps.count - 1 {
                        Rectangle().fill(DS.border).frame(height: 1)
                            .padding(.leading, 24)
                    }
                }
            }

            HStack {
                if practice.count > 0, let last = practice.lastDate {
                    Text("PRACTICED \(practice.count)× · LAST \(last.formatted(.dateTime.day().month()).uppercased())")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                        .tracking(1.0)
                        .foregroundStyle(DS.severityMinor)
                }
                Spacer()
                Button(action: onMarkDone) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .accessibilityHidden(true)
                        Text("MARK DONE")
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                            .tracking(1.2)
                    }
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(DS.accent.opacity(0.45), lineWidth: 1))
                    // Pill stays visually compact; the frame extends the
                    // tap target to the HIG 44pt minimum.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark \(drill.name) done today")
            }
            .padding(.top, 2)
        }
        .padding(16)
        .glassCard(borderColor: isHighlighted ? DS.accent : DS.border)
        .accessibilityElement(children: .combine)
    }
}
