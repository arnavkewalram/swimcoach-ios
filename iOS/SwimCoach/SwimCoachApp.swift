import SwiftUI
import SwiftData

@main
struct SwimCoachApp: App {
    let container: ModelContainer

    init() {
        container = try! ModelContainer(for: SwimSession.self, DrillPracticeEvent.self)
        // Nothing else belongs here: `init()` runs before the first Scene is
        // built, so any work it does is time the user spends on a blank
        // screen. Storage hygiene moved to a background task on RootView.
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
