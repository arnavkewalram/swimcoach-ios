import XCTest
@testable import SwimCoach

/// Retention for clips the store adopted but no session ever claimed.
///
/// Two failure modes bracket this policy, and both are expensive:
///   • sweeping too eagerly destroys a lap the user actually filmed (the bug
///     this closes — the old sweeper deleted every unclaimed file at launch);
///   • sweeping a *claimed* file breaks playback for a saved session, which is
///     data loss the user can see in History forever.
/// The decision is pure so both can be pinned without a filesystem.
final class UnfinishedTakesTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func file(_ id: UUID = UUID(),
                      ext: String = "mov",
                      ageSeconds: TimeInterval,
                      bytes: Int64 = 1024) -> UnfinishedTakes.StoredFile {
        UnfinishedTakes.StoredFile(name: "\(id.uuidString).\(ext)",
                                   modifiedAt: now.addingTimeInterval(-ageSeconds),
                                   byteCount: bytes)
    }

    private func classify(_ files: [UnfinishedTakes.StoredFile],
                          referencedIDs: Set<String> = []) -> UnfinishedTakes.Classification {
        UnfinishedTakes.classify(files: files, referencedIDs: referencedIDs, now: now)
    }

    // MARK: - Inside the window

    func testFreshUnclaimedClipIsRecoverableNotSwept() {
        let id = UUID()
        let result = classify([file(id, ageSeconds: 60)])

        XCTAssertEqual(result.takes.map(\.id), [id],
                       "A clip filmed a minute ago must be offered back, not deleted")
        XCTAssertTrue(result.expired.isEmpty)
    }

    func testClipJustInsideTheWindowSurvives() {
        let id = UUID()
        let result = classify([file(id, ageSeconds: UnfinishedTakes.retention - 1)])

        XCTAssertEqual(result.takes.map(\.id), [id])
        XCTAssertTrue(result.expired.isEmpty)
    }

    /// The boundary itself is inclusive — a take is kept *for* the window, not
    /// until just before it.
    func testClipExactlyOnTheBoundarySurvives() {
        let id = UUID()
        let result = classify([file(id, ageSeconds: UnfinishedTakes.retention)])

        XCTAssertEqual(result.takes.map(\.id), [id])
    }

    /// A device clock that jumped backwards makes the clip look "newer than
    /// now". Retaining is the only safe direction.
    func testFutureDatedClipIsRetainedRatherThanSwept() {
        let id = UUID()
        let result = classify([file(id, ageSeconds: -3600)])

        XCTAssertEqual(result.takes.map(\.id), [id])
        XCTAssertTrue(result.expired.isEmpty)
    }

    // MARK: - Outside the window

    func testClipPastTheWindowExpires() {
        let stale = file(ageSeconds: UnfinishedTakes.retention + 1)
        let result = classify([stale])

        XCTAssertTrue(result.takes.isEmpty)
        XCTAssertEqual(result.expired, [stale.name],
                       "Pruning must still remove genuinely expired files")
    }

    func testLongExpiredClipStillExpires() {
        let ancient = file(ageSeconds: 400 * 24 * 60 * 60)
        XCTAssertEqual(classify([ancient]).expired, [ancient.name])
    }

    func testWindowSplitsAMixedDirectory() {
        let fresh = file(ageSeconds: 3600)
        let stale = file(ageSeconds: UnfinishedTakes.retention * 2)
        let result = classify([fresh, stale])

        XCTAssertEqual(result.takes.map(\.fileName), [fresh.name])
        XCTAssertEqual(result.expired, [stale.name])
    }

    /// The window is a parameter, so a caller (or a future policy change) can
    /// move it without the classification changing shape.
    func testRetentionWindowIsHonouredWhenOverridden() {
        let clip = file(ageSeconds: 2 * 3600)
        let kept = UnfinishedTakes.classify(files: [clip], referencedIDs: [],
                                            now: now, retention: 3 * 3600)
        let dropped = UnfinishedTakes.classify(files: [clip], referencedIDs: [],
                                               now: now, retention: 1 * 3600)

        XCTAssertEqual(kept.takes.count, 1)
        XCTAssertEqual(dropped.expired, [clip.name])
    }

    // MARK: - Claimed sessions are untouchable

    func testClaimedSessionVideoIsNeverListed() {
        let id = UUID()
        let result = classify([file(id, ageSeconds: 60)], referencedIDs: [id.uuidString])

        XCTAssertTrue(result.takes.isEmpty,
                      "A saved session's video is not an unfinished take")
    }

    /// The load-bearing one: age must never reach a claimed file. A session
    /// recorded a year ago still plays back in History.
    func testClaimedSessionVideoIsNeverExpiredNoMatterHowOld() {
        let id = UUID()
        let result = classify([file(id, ageSeconds: 10 * 365 * 24 * 60 * 60)],
                              referencedIDs: [id.uuidString])

        XCTAssertTrue(result.expired.isEmpty,
                      "A claimed session's video must never be deleted")
        XCTAssertTrue(result.takes.isEmpty)
    }

    func testClaimedAndUnclaimedFilesAreSeparatedInOnePass() {
        let claimed = UUID(), waiting = UUID(), gone = UUID()
        let result = classify([
            file(claimed, ageSeconds: 99 * 24 * 60 * 60),
            file(waiting, ageSeconds: 2 * 24 * 60 * 60),
            file(gone, ageSeconds: 30 * 24 * 60 * 60),
        ], referencedIDs: [claimed.uuidString])

        XCTAssertEqual(result.takes.map(\.id), [waiting])
        XCTAssertEqual(result.expired, ["\(gone.uuidString).mov"])
    }

    /// Membership is decided on the basename, so the extension a capture
    /// happened to carry cannot make a claimed video look sweepable.
    func testClaimIgnoresTheExtension() {
        let id = UUID()
        for ext in ["mov", "mp4", "m4v", "MOV"] {
            let result = classify([file(id, ext: ext, ageSeconds: 60)],
                                  referencedIDs: [id.uuidString])
            XCTAssertTrue(result.takes.isEmpty && result.expired.isEmpty,
                          "\(ext) file misclassified despite a live session")
        }
    }

    // MARK: - Ordering

    func testTakesAreNewestFirst() {
        let oldest = file(ageSeconds: 5 * 24 * 60 * 60)
        let middle = file(ageSeconds: 2 * 24 * 60 * 60)
        let newest = file(ageSeconds: 60)

        let result = classify([oldest, newest, middle])

        XCTAssertEqual(result.takes.map(\.fileName), [newest.name, middle.name, oldest.name])
    }

    /// Two takes sharing a filesystem timestamp must still order the same way
    /// on every launch — a list that reshuffles itself is a list nobody trusts.
    func testTakesWithIdenticalTimestampsOrderDeterministically() {
        // Non-id names would be debris, so this needs real ids at one instant.
        let ids = [UUID(), UUID()].sorted { $0.uuidString < $1.uuidString }
        let files = ids.map {
            UnfinishedTakes.StoredFile(name: "\($0.uuidString).mov", modifiedAt: now, byteCount: 1)
        }

        XCTAssertEqual(classify(files).takes.map(\.id), ids)
        XCTAssertEqual(classify(files.reversed()).takes.map(\.id), ids,
                       "Directory order must not decide the list order")
    }

    // MARK: - Empty and degenerate cases

    func testEmptyStoreYieldsNothing() {
        let result = classify([])
        XCTAssertTrue(result.takes.isEmpty)
        XCTAssertTrue(result.expired.isEmpty)
    }

    func testStoreOfOnlyClaimedVideosYieldsNothing() {
        let ids = (0..<3).map { _ in UUID() }
        let result = classify(ids.map { file($0, ageSeconds: 3600) },
                              referencedIDs: Set(ids.map(\.uuidString)))

        XCTAssertTrue(result.takes.isEmpty)
        XCTAssertTrue(result.expired.isEmpty)
    }

    /// Nothing has ever written a non-id name into the store, so debris is not
    /// offered to the user as a swim — it expires on sight, however fresh.
    func testDebrisIsExpiredImmediatelyRatherThanListed() {
        let debris = [
            UnfinishedTakes.StoredFile(name: ".DS_Store", modifiedAt: now),
            UnfinishedTakes.StoredFile(name: "legacy-clip.mov", modifiedAt: now),
            UnfinishedTakes.StoredFile(name: "swim_test.mp4", modifiedAt: now),
        ]

        let result = classify(debris)

        XCTAssertTrue(result.takes.isEmpty)
        XCTAssertEqual(Set(result.expired), Set(debris.map(\.name)))
    }

    // MARK: - Take payload

    func testTakeCarriesTheIDItsFileIsNamedAfter() throws {
        let id = UUID()
        let take = try XCTUnwrap(
            classify([file(id, ext: "mp4", ageSeconds: 120, bytes: 4_096)]).takes.first)

        XCTAssertEqual(take.id, id, "Re-analysis reuses this id to keep the filename invariant")
        XCTAssertEqual(take.fileName, "\(id.uuidString).mp4")
        XCTAssertEqual(take.byteCount, 4_096)
        XCTAssertEqual(take.capturedAt, now.addingTimeInterval(-120))
    }
}

// MARK: - Store integration

/// The filesystem half: the store has to produce records the pure decision can
/// act on, and act on its verdict without touching a claimed video.
final class UnfinishedTakesStoreTests: XCTestCase {

    private var written: [URL] = []

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
        super.tearDown()
    }

    @discardableResult
    private func writeStoredClip(id: UUID = UUID(),
                                 ext: String = "mov",
                                 ageSeconds: TimeInterval = 0) throws -> URL {
        let url = SessionVideoStore.directory
            .appendingPathComponent("\(id.uuidString).\(ext)")
        try Data("fake-movie".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-ageSeconds)],
            ofItemAtPath: url.path)
        written.append(url)
        return url
    }

    /// Everything already in the store when a test starts — other suites and
    /// earlier runs leave files behind, so assertions scope to their own ids.
    private func storedNames() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(
            atPath: SessionVideoStore.directory.path)) ?? [])
    }

    func testRecentUnclaimedClipIsListedAsAnUnfinishedTake() throws {
        let id = UUID()
        try writeStoredClip(id: id, ageSeconds: 3600)

        let takes = SessionVideoStore.unfinishedTakes(referencedIDs: [])

        XCTAssertTrue(takes.contains { $0.id == id })
    }

    func testClaimedClipIsNotListed() throws {
        let id = UUID()
        try writeStoredClip(id: id, ageSeconds: 3600)

        let takes = SessionVideoStore.unfinishedTakes(referencedIDs: [id.uuidString])

        XCTAssertFalse(takes.contains { $0.id == id })
    }

    func testPruneKeepsARecentTakeAndRemovesAnExpiredOne() throws {
        let keep = UUID(), sweep = UUID()
        let keepURL = try writeStoredClip(id: keep, ageSeconds: 2 * 24 * 60 * 60)
        let sweepURL = try writeStoredClip(id: sweep,
                                           ageSeconds: UnfinishedTakes.retention + 60)

        SessionVideoStore.pruneOrphans(referencedIDs: [])

        XCTAssertTrue(FileManager.default.fileExists(atPath: keepURL.path),
                      "A take inside the window must survive the launch sweep")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sweepURL.path),
                       "An expired take must still be pruned")
    }

    func testPruneNeverRemovesAClaimedSessionVideo() throws {
        let id = UUID()
        let url = try writeStoredClip(id: id, ageSeconds: 5 * 365 * 24 * 60 * 60)

        SessionVideoStore.pruneOrphans(referencedIDs: [id.uuidString])

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "A five-year-old video a session still references must survive")
    }

    /// The whole point of reusing the take's id: `persist` recognises the file
    /// as already stored under the right name, so the second pass produces no
    /// duplicate and the saved session claims the original.
    func testReanalyzingATakePreservesTheFilenameInvariant() throws {
        let id = UUID()
        let url = try writeStoredClip(id: id, ext: "mp4", ageSeconds: 600)
        let take = try XCTUnwrap(
            SessionVideoStore.unfinishedTakes(referencedIDs: []).first { $0.id == id })

        let clip = SessionVideoStore.pendingClip(for: take)
        let persistedName = SessionVideoStore.persist(clip.url, for: clip.id)

        XCTAssertEqual(clip.id, id)
        XCTAssertEqual(clip.url.standardizedFileURL, url.standardizedFileURL)
        XCTAssertEqual(persistedName, "\(id.uuidString).mp4")
        XCTAssertEqual(storedNames().filter { $0.hasPrefix(id.uuidString) }.count, 1,
                       "Re-analysis must not leave a second copy behind")
        XCTAssertTrue(SessionVideoStore.orphanedFileNames(
            among: [persistedName ?? ""], referencedIDs: [id.uuidString]).isEmpty)
    }

    func testDeletingATakeRemovesItImmediately() throws {
        let id = UUID()
        let url = try writeStoredClip(id: id, ageSeconds: 60)
        let take = try XCTUnwrap(
            SessionVideoStore.unfinishedTakes(referencedIDs: []).first { $0.id == id })

        SessionVideoStore.delete(take)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Erase everything

    /// Retention is a policy for clips nobody has decided about. "Erase
    /// everything" is a decision, and About promises "this cannot be undone" —
    /// so it must outrank the window the launch sweep respects.
    func testEraseRemovesAClipTooFreshForTheSweeperToTouch() throws {
        let id = UUID()
        let url = try writeStoredClip(id: id, ageSeconds: 60)

        SessionVideoStore.removeAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "A clip filmed a minute ago must not survive an explicit erase")
    }

    /// The sessions are deleted before the videos are, so by the time erase
    /// reaches the store every file looks unclaimed. A claimed video has to go
    /// too — that is the half of the promise the dialog spells out ("every
    /// saved session and its video").
    func testEraseRemovesAClaimedSessionVideoToo() throws {
        let id = UUID()
        let url = try writeStoredClip(id: id, ageSeconds: 3600)

        SessionVideoStore.removeAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "The video of an erased session must be deleted with it")
    }

    /// The resurrection symptom: videos that outlive an erase are unclaimed by
    /// construction, so Home offers the swims the user just erased straight
    /// back as recoverable takes.
    func testEraseLeavesNothingForRecoveryToSurface() throws {
        let fresh = UUID(), older = UUID()
        try writeStoredClip(id: fresh, ageSeconds: 60)
        try writeStoredClip(id: older, ext: "mp4", ageSeconds: 3 * 24 * 60 * 60)

        SessionVideoStore.removeAll()

        let takes = SessionVideoStore.unfinishedTakes(referencedIDs: [])
        XCTAssertFalse(takes.contains { $0.id == fresh || $0.id == older },
                       "An erased swim must not come back as an unfinished take")
    }

    func testEraseEmptiesTheStoreOutright() throws {
        try writeStoredClip(ageSeconds: 30)
        try writeStoredClip(ageSeconds: UnfinishedTakes.retention * 2)
        try writeStoredClip(ext: "mp4", ageSeconds: 6 * 24 * 60 * 60)

        SessionVideoStore.removeAll()

        XCTAssertTrue(storedNames().isEmpty,
                      "Erase sweeps the whole store, whatever age or claim state")
    }

    /// The failure path: a clip adopted at record time is still there after an
    /// analysis that never saved a session, and it is listed rather than gone.
    func testAdoptedClipSurvivesAnAnalysisThatNeverClaimedIt() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        try Data("fake-movie".utf8).write(to: source)
        let clip = SessionVideoStore.adopt(source)
        written.append(clip.url)

        // No session was ever saved for this clip; the next launch sweeps.
        SessionVideoStore.pruneOrphans(referencedIDs: [])

        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.url.path))
        XCTAssertTrue(SessionVideoStore.unfinishedTakes(referencedIDs: [])
            .contains { $0.id == clip.id })
    }
}
