import SwiftUI
import SwiftData

@main
struct SwimCoachApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: SwimSession.self)
    }
}
