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
    /// Keep-or-retake preview of a just-recorded clip, between camera and
    /// analysis. Carries the adopted clip so the id survives the decision.
    case review(PendingClip)
    case analyzing(PendingClip)
    case results(AnalysisResult)
    case history
    case compare(earlier: AnalysisResult, later: AnalysisResult)
    case report(AnalysisResult)
    case drills(highlightIssue: String?)
    /// Clips adopted into the store that no session ever claimed, still inside
    /// their retention window.
    case unfinishedTakes
    case about
}
