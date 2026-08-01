import SwiftUI

@Observable
final class AppRouter {
    var path = NavigationPath()

    func push(_ destination: AppDestination) {
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
