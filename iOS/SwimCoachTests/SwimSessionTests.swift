import XCTest
import SwiftData
@testable import SwimCoach

final class SwimSessionTests: XCTestCase {

    @MainActor
    func testNotesRoundTripThroughStore() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SwimSession.self, configurations: config)
        let context = container.mainContext

        let session = SwimSession(result: .demo)
        context.insert(session)
        session.name = "Tuesday threshold"
        session.notes = "Worked on catch; felt heavy after 200m"
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SwimSession>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Tuesday threshold")
        XCTAssertEqual(fetched.first?.notes, "Worked on catch; felt heavy after 200m")
    }

    @MainActor
    func testNotesDefaultsEmptyForNewSessions() throws {
        let session = SwimSession(result: .demo)
        XCTAssertEqual(session.notes, "")
    }
}
