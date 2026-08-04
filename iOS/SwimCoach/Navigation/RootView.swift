import SwiftUI

struct RootView: View {
    @State private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        @Bindable var r = router
        NavigationStack(path: $r.path) {
            HomeView()
                .navigationDestination(for: AppDestination.self) { dest in
                    switch dest {
                    case .camera:
                        CameraView()
                    case .review(let clip):
                        ReviewView(clip: clip)
                    case .analyzing(let clip):
                        AnalyzingView(clip: clip)
                    case .results(let result):
                        ResultsView(result: result)
                    case .history:
                        HistoryView()
                    case .compare(let earlier, let later):
                        CompareView(earlier: earlier, later: later)
                    case .drills(let highlightIssue):
                        DrillsView(highlightIssue: highlightIssue)
                    case .about:
                        AboutView()
                    case .report(let result):
                        #if DEBUG
                        ReportScreen(result: result,
                                     trendScores: [58, 61, 60, 64, 63, 67, 66, 70, 69, 72],
                                     newBest: true)
                        #else
                        ReportScreen(result: result)
                        #endif
                    }
                }
        }
        .environment(router)
        // Storage hygiene, deliberately off the launch path. This used to run
        // inside `SwimCoachApp.init()` — before any Scene existed — and
        // decoded every session's externally-stored result blob (a disk read
        // plus a full JSON pass over ~¼ MB of keypoint frames each) purely to
        // read one file name. It now runs once per launch, after first paint,
        // on the cooperative pool with its own ModelContext, and derives the
        // referenced set from the cheap stored `id` column instead.
        .task(priority: .background) {
            await SessionVideoStore.pruneOrphans(in: modelContext.container)
        }
        // Weekly goal reminder copy embeds the live session count, which a
        // calendar trigger can't know — refresh the pending request every
        // time the app comes to the foreground (initial launch included).
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            GoalReminder.reschedule(context: modelContext)
        }
        // Follows the system appearance: light is the "meet sheet"
        // editorial; dark is "Night Meet" (see DesignSystem.swift).
        // Dynamic Type scales everywhere; capped at accessibility2 so the
        // data-dense layouts degrade gracefully instead of shattering.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}
