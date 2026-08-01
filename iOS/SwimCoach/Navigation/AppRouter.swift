import SwiftUI

@Observable
final class AppRouter {
    var path = NavigationPath()

    func push(_ destination: AppDestination) {
        path.append(destination)
    }

    /// Replace the top of the stack — used when a transient screen (Analyzing)
    /// hands off to its result so that Back skips the transient screen instead
    /// of re-running it.
    func replaceTop(with destination: AppDestination) {
        if !path.isEmpty { path.removeLast() }
        path.append(destination)
    }

    func popToRoot() {
        path.removeLast(path.count)
    }
}

enum AppDestination: Hashable {
    case camera
    case analyzing(URL)
    case results(AnalysisResult)
    case history
}
