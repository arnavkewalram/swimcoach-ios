import SwiftUI
import SwiftData

@main
struct SwimCoachApp: App {
    let container: ModelContainer

    init() {
        container = try! ModelContainer(for: SwimSession.self)
        // Storage hygiene: drop session videos whose session no longer exists.
        let context = ModelContext(container)
        if let sessions = try? context.fetch(FetchDescriptor<SwimSession>()) {
            let referenced = Set(sessions.compactMap { $0.decoded()?.videoFileName })
            SessionVideoStore.pruneOrphans(referencedFileNames: referenced)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
