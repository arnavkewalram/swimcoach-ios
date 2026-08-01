import SwiftUI

struct RootView: View {
    @State private var router = AppRouter()

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
                    }
                }
        }
        .environment(router)
        // Deliberate single-appearance design: light "meet sheet" editorial.
        .preferredColorScheme(.light)
    }
}
