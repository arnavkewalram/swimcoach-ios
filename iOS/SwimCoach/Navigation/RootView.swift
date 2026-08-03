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
                    case .analyzing(let url):
                        AnalyzingView(videoURL: url)
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
