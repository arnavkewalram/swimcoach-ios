import XCTest
import SwiftData
@testable import SwimCoach

/// The policy that decides which video files are destroyed.
///
/// Every other part of this feature degrades safely — a missing clip already
/// resolves to a nil `videoURL`, Results already drops its video section. The
/// data loss, if there is any, lives entirely in this decision, so it is tested
/// without a filesystem: file records in, names out.
///
/// The invariant under everything below: **a file is only ever a candidate if
/// a saved session claims it.** An unclaimed file is an unfinished take whose
/// video IS the swim; deleting it here would lose the swim, which is the
/// opposite of what this feature offers.
final class VideoStorageTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    // MARK: - Fixtures

    private func clip(_ id: UUID = UUID(), daysAgo: Double,
                      bytes: Int64 = 10_000_000,
                      ext: String = "mov") -> UnfinishedTakes.StoredFile {
        UnfinishedTakes.StoredFile(name: "\(id.uuidString).\(ext)",
                                   modifiedAt: now.addingTimeInterval(-daysAgo * day),
                                   byteCount: bytes)
    }

    private func ids(_ files: [UnfinishedTakes.StoredFile]) -> Set<String> {
        Set(files.map { ($0.name as NSString).deletingPathExtension })
    }

    private func cutoff(days: Int?) -> VideoStorage.Cutoff {
        VideoStorage.cutoffs.first { $0.days == days }!
    }

    private var anyAge: VideoStorage.Cutoff { cutoff(days: nil) }

    // MARK: - Nothing stored

    func testEmptyStoreSummarizesToNothingAndOffersNothing() {
        let summary = VideoStorage.summarize(files: [], referencedIDs: [], now: now)

        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(summary.totalByteCount, 0)
        XCTAssertEqual(summary.fileCount, 0)
        XCTAssertFalse(summary.hasDeletableClips,
                       "An empty store must not offer a delete that would remove nothing")
        XCTAssertNil(summary.defaultCutoff)
        XCTAssertEqual(summary.offers.count, VideoStorage.cutoffs.count)
        XCTAssertTrue(summary.offers.allSatisfy(\.isEmpty))
    }

    func testEmptySummaryConstantMatchesSummarizingNoFiles() {
        XCTAssertTrue(VideoStorage.Summary.empty.isEmpty)
        XCTAssertFalse(VideoStorage.Summary.empty.hasDeletableClips)
        XCTAssertNil(VideoStorage.Summary.empty.defaultCutoff)
        XCTAssertEqual(VideoStorage.Summary.empty.totalByteCount, 0)
    }

    // MARK: - Everything younger than the cutoff

    func testClipsYoungerThanEveryDatedCutoffAreNotOffered() {
        let files = [clip(daysAgo: 0), clip(daysAgo: 3), clip(daysAgo: 29.5)]
        let summary = VideoStorage.summarize(files: files, referencedIDs: ids(files), now: now)

        for days in [365, 90, 30] {
            XCTAssertTrue(summary.offer(for: cutoff(days: days)).isEmpty,
                          "A clip filmed days ago must not be offered under a \(days)-day cutoff")
        }
        // "Any age" is the whole point of the row: it has no window to be
        // younger than.
        XCTAssertEqual(summary.offer(for: anyAge).count, 3)
        XCTAssertEqual(summary.defaultCutoff, anyAge,
                       "The safe default is the most conservative offer that frees anything")
    }

    // MARK: - Everything older than the cutoff

    func testClipsOlderThanEveryCutoffAreOfferedByAllOfThem() {
        let files = [clip(daysAgo: 400, bytes: 1), clip(daysAgo: 900, bytes: 2)]
        let summary = VideoStorage.summarize(files: files, referencedIDs: ids(files), now: now)

        for offer in summary.offers {
            XCTAssertEqual(offer.count, 2, "\(offer.cutoff.label) missed a clip older than itself")
            XCTAssertEqual(offer.byteCount, 3)
        }
        XCTAssertEqual(summary.defaultCutoff?.days, 365)
    }

    /// Each row strictly includes the one above it, so the list reads as
    /// increasing destructiveness rather than four unrelated buttons.
    func testOffersNestFromMostConservativeToLeast() {
        let files = [clip(daysAgo: 1), clip(daysAgo: 45), clip(daysAgo: 120), clip(daysAgo: 500)]
        let summary = VideoStorage.summarize(files: files, referencedIDs: ids(files), now: now)

        XCTAssertEqual(summary.offers.map(\.count), [1, 2, 3, 4])
        for (narrow, wide) in zip(summary.offers, summary.offers.dropFirst()) {
            XCTAssertTrue(Set(narrow.fileNames).isSubset(of: Set(wide.fileNames)),
                          "\(wide.cutoff.label) must include everything \(narrow.cutoff.label) does")
            XCTAssertLessThanOrEqual(narrow.byteCount, wide.byteCount)
        }
    }

    // MARK: - Claimed vs unclaimed

    func testAnUnclaimedTakeIsCountedButNeverDeleted() {
        let claimed = clip(daysAgo: 500, bytes: 7)
        let take = clip(daysAgo: 500, bytes: 11)

        let summary = VideoStorage.summarize(files: [claimed, take],
                                             referencedIDs: ids([claimed]), now: now)

        XCTAssertEqual(summary.totalByteCount, 18, "The headline total must cover the whole store")
        XCTAssertEqual(summary.fileCount, 2)
        XCTAssertEqual(summary.sessionClipCount, 1)
        XCTAssertEqual(summary.sessionClipByteCount, 7)
        XCTAssertEqual(summary.unscoredCount, 1)
        XCTAssertEqual(summary.unscoredByteCount, 11)
        for offer in summary.offers {
            XCTAssertEqual(offer.fileNames, [claimed.name],
                           "\(offer.cutoff.label) nominated an unclaimed take — that loses the swim")
        }
    }

    /// The trap in miniature: a store where nothing is claimed must produce no
    /// delete offer at all, however old the files are.
    func testAStoreOfOnlyTakesOffersNothingToDelete() {
        let files = [clip(daysAgo: 900), clip(daysAgo: 2000)]

        let summary = VideoStorage.summarize(files: files, referencedIDs: [], now: now)

        XCTAssertFalse(summary.isEmpty)
        XCTAssertEqual(summary.sessionClipCount, 0)
        XCTAssertEqual(summary.unscoredCount, 2)
        XCTAssertFalse(summary.hasDeletableClips)
        XCTAssertNil(summary.defaultCutoff)
    }

    /// `persist` keeps the source extension, so membership is decided on the
    /// basename — a session's `.mp4` must be as claimable as its `.mov`.
    func testClaimMatchIgnoresTheExtension() {
        for ext in ["mov", "mp4", "m4v"] {
            let file = clip(daysAgo: 500, ext: ext)
            let summary = VideoStorage.summarize(files: [file],
                                                 referencedIDs: ids([file]), now: now)
            XCTAssertEqual(summary.sessionClipCount, 1, "\(ext) was not recognised as claimed")
            XCTAssertEqual(summary.offer(for: anyAge).fileNames, [file.name])
        }
    }

    /// Debris (a `.DS_Store`, a legacy name) is not a session clip and is not
    /// a take either. It is counted so the total reconciles with the store,
    /// and left to the launch sweep.
    func testDebrisIsCountedButNeverDeleted() {
        let debris = UnfinishedTakes.StoredFile(name: ".DS_Store",
                                                modifiedAt: now.addingTimeInterval(-900 * day),
                                                byteCount: 6_148)
        let summary = VideoStorage.summarize(files: [debris], referencedIDs: [], now: now)

        XCTAssertEqual(summary.totalByteCount, 6_148)
        XCTAssertEqual(summary.unscoredCount, 1)
        XCTAssertFalse(summary.hasDeletableClips)
    }

    // MARK: - The boundary

    func testAClipExactlyAtTheCutoffAgeIsKept() {
        let file = clip(daysAgo: 30)
        let summary = VideoStorage.summarize(files: [file], referencedIDs: ids([file]), now: now)

        XCTAssertTrue(summary.offer(for: cutoff(days: 30)).isEmpty,
                      "Exactly 30 days old is not yet OLDER than 30 days — the boundary keeps it, "
                      + "matching UnfinishedTakes, whose window is inclusive too")
    }

    func testAClipOneSecondPastTheCutoffIsOffered() {
        let file = UnfinishedTakes.StoredFile(
            name: "\(UUID().uuidString).mov",
            modifiedAt: now.addingTimeInterval(-(30 * day + 1)),
            byteCount: 5)
        let summary = VideoStorage.summarize(files: [file], referencedIDs: ids([file]), now: now)

        XCTAssertEqual(summary.offer(for: cutoff(days: 30)).fileNames, [file.name])
    }

    func testTheYearBoundaryIs365Days() {
        let atBoundary = clip(daysAgo: 365)
        let past = clip(daysAgo: 366)
        let summary = VideoStorage.summarize(files: [atBoundary, past],
                                             referencedIDs: ids([atBoundary, past]), now: now)

        XCTAssertEqual(summary.offer(for: cutoff(days: 365)).fileNames, [past.name])
    }

    /// A clock that jumped backwards makes the age negative. Keeping is the
    /// safe direction, and a negative age fails the comparison outright.
    func testAClipWithAFutureTimestampIsNeverAgedOut() {
        let file = clip(daysAgo: -10)
        let summary = VideoStorage.summarize(files: [file], referencedIDs: ids([file]), now: now)

        for days in [365, 90, 30] {
            XCTAssertTrue(summary.offer(for: cutoff(days: days)).isEmpty)
        }
        XCTAssertEqual(summary.offer(for: anyAge).count, 1,
                       "An explicit ANY AGE request still covers it")
    }

    /// `SessionVideoStore.storedFiles` substitutes `.distantPast` when the
    /// filesystem cannot vouch for a file's age. That reads as very old here,
    /// which is the same direction retention already takes it.
    func testAnUndatedClipCountsAsOld() {
        let file = UnfinishedTakes.StoredFile(name: "\(UUID().uuidString).mov",
                                              modifiedAt: .distantPast, byteCount: 3)
        let summary = VideoStorage.summarize(files: [file], referencedIDs: ids([file]), now: now)

        XCTAssertTrue(summary.offers.allSatisfy { $0.fileNames == [file.name] })
    }

    // MARK: - The empty delete set

    func testAnEmptyOfferCarriesNoNamesAndNoBytes() {
        let file = clip(daysAgo: 2, bytes: 500)
        let summary = VideoStorage.summarize(files: [file], referencedIDs: ids([file]), now: now)

        let offer = summary.offer(for: cutoff(days: 90))
        XCTAssertTrue(offer.isEmpty)
        XCTAssertEqual(offer.count, 0)
        XCTAssertEqual(offer.byteCount, 0, "An empty offer must not price bytes it will not free")
    }

    func testDefaultCutoffSkipsTheOffersThatWouldDeleteNothing() {
        let file = clip(daysAgo: 100)
        let summary = VideoStorage.summarize(files: [file], referencedIDs: ids([file]), now: now)

        XCTAssertEqual(summary.defaultCutoff?.days, 90,
                       "A year frees nothing here, so the default must fall through to 90 days")
        XCTAssertTrue(summary.offer(for: cutoff(days: 365)).isEmpty)
    }

    func testOfferForAnUnknownCutoffIsEmptyRatherThanCrashing() {
        let stray = VideoStorage.Cutoff(days: 7, label: "A WEEK", phrase: "", spoken: "a week")
        let summary = VideoStorage.summarize(files: [clip(daysAgo: 900)],
                                             referencedIDs: [], now: now)

        XCTAssertTrue(summary.offer(for: stray).isEmpty)
    }

    // MARK: - Determinism and shape

    func testSelectionIsOrderedOldestFirst() {
        let a = clip(daysAgo: 40), b = clip(daysAgo: 900), c = clip(daysAgo: 100)
        let files = [a, b, c]

        let selection = VideoStorage.selection(files: files, referencedIDs: ids(files),
                                               olderThan: anyAge, now: now)

        XCTAssertEqual(selection.fileNames, [b.name, c.name, a.name])
    }

    func testSelectionMatchesTheOfferInTheSummary() {
        let files = [clip(daysAgo: 1), clip(daysAgo: 200)]
        let referenced = ids(files)

        for cutoff in VideoStorage.cutoffs {
            XCTAssertEqual(
                VideoStorage.selection(files: files, referencedIDs: referenced,
                                       olderThan: cutoff, now: now),
                VideoStorage.summarize(files: files, referencedIDs: referenced, now: now)
                    .offer(for: cutoff),
                "The summary priced \(cutoff.label) differently from the delete that follows it")
        }
    }

    func testOffersAreOrderedMostConservativeFirst() {
        XCTAssertEqual(VideoStorage.cutoffs.map(\.days), [365, 90, 30, nil])
        XCTAssertEqual(VideoStorage.cutoffs.map(\.label), ["A YEAR", "90 DAYS", "30 DAYS", "ANY AGE"])
        XCTAssertEqual(Set(VideoStorage.cutoffs.map(\.id)).count, VideoStorage.cutoffs.count,
                       "Cutoff ids drive ForEach identity — they have to be unique")
    }

    // MARK: - Formatting

    func testSizeTextUsesTheSystemFormatterAndSaysItsUnit() {
        XCTAssertTrue(VideoStorage.sizeText(210_000_000).hasSuffix("MB"),
                      "got \(VideoStorage.sizeText(210_000_000))")
        XCTAssertTrue(VideoStorage.sizeText(4_100_000_000).hasSuffix("GB"),
                      "got \(VideoStorage.sizeText(4_100_000_000))")
        XCTAssertFalse(VideoStorage.sizeText(0).isEmpty)
    }

    func testClipCountTextPluralises() {
        XCTAssertEqual(VideoStorage.clipCountText(0), "0 clips")
        XCTAssertEqual(VideoStorage.clipCountText(1), "1 clip")
        XCTAssertEqual(VideoStorage.clipCountText(9), "9 clips")
    }
}

// MARK: - The filesystem half

/// The store has to act on the pure verdict without touching a session, and
/// without handing anything back to the retention machinery.
///
/// v1.45.3 fixed a bug where erased clips came back as recoverable takes: files
/// outlived the sessions that claimed them, so every survivor looked unclaimed.
/// This delete is the mirror image — the files go and the sessions stay — and
/// these tests pin that it stays that way.
final class VideoStorageStoreTests: XCTestCase {

    private var written: [URL] = []

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
        super.tearDown()
    }

    @discardableResult
    private func writeStoredClip(id: UUID = UUID(), ext: String = "mov",
                                 daysAgo: Double = 0, bytes: Int = 1_024) throws -> URL {
        let url = SessionVideoStore.directory
            .appendingPathComponent("\(id.uuidString).\(ext)")
        try Data(repeating: 7, count: bytes).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-daysAgo * 24 * 60 * 60)],
            ofItemAtPath: url.path)
        written.append(url)
        return url
    }

    private func cutoff(days: Int?) -> VideoStorage.Cutoff {
        VideoStorage.cutoffs.first { $0.days == days }!
    }

    /// The screen's own two steps, in order: price the store, then delete the
    /// offer that was priced. Tests go through both so they exercise the same
    /// hand-off the UI does rather than a shortcut only they can take.
    @discardableResult
    private func priceThenDelete(days: Int?, referencedIDs: Set<String>) -> [String] {
        let offer = SessionVideoStore.storageSummary(referencedIDs: referencedIDs)
            .offer(for: cutoff(days: days))
        return SessionVideoStore.deleteSessionClips(offer, referencedIDs: referencedIDs)
    }

    // MARK: - Sizes for claimed files

    func testSummaryReportsTheBytesOfAClaimedClip() throws {
        let id = UUID()
        try writeStoredClip(id: id, daysAgo: 200, bytes: 4_096)

        let summary = SessionVideoStore.storageSummary(referencedIDs: [id.uuidString])
        let offer = summary.offer(for: cutoff(days: 90))

        XCTAssertTrue(offer.fileNames.contains("\(id.uuidString).mov"))
        XCTAssertGreaterThanOrEqual(offer.byteCount, 4_096,
                                    "A claimed file's size used to be computed and thrown away")
        XCTAssertGreaterThanOrEqual(summary.totalByteCount, 4_096)
    }

    // MARK: - Delete

    func testDeleteRemovesTheOldClipAndKeepsTheRecentOne() throws {
        let old = UUID(), recent = UUID()
        let oldURL = try writeStoredClip(id: old, daysAgo: 400)
        let recentURL = try writeStoredClip(id: recent, daysAgo: 2)

        let removed = priceThenDelete(days: 90,
                                      referencedIDs: [old.uuidString, recent.uuidString])

        XCTAssertEqual(removed, ["\(old.uuidString).mov"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentURL.path))
    }

    func testDeleteAtAnyAgeEmptiesEveryClaimedClipButLeavesTheTakes() throws {
        let claimedA = UUID(), claimedB = UUID(), take = UUID()
        let a = try writeStoredClip(id: claimedA, daysAgo: 0)
        let b = try writeStoredClip(id: claimedB, ext: "mp4", daysAgo: 3)
        let takeURL = try writeStoredClip(id: take, daysAgo: 1)

        priceThenDelete(days: nil,
                        referencedIDs: [claimedA.uuidString, claimedB.uuidString])

        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: takeURL.path),
                      "An unfinished take is a swim that only exists as video — it is not ours to drop")
    }

    /// The v1.45.3 symptom, asserted directly: a clip this control deletes must
    /// not come back on Home as something to recover.
    func testDeletedClipsDoNotReappearAsUnfinishedTakes() throws {
        let id = UUID()
        try writeStoredClip(id: id, daysAgo: 400)

        priceThenDelete(days: 90, referencedIDs: [id.uuidString])

        // The session still exists, so the id is still referenced — and the
        // file is gone, so the listing cannot surface it either way.
        XCTAssertFalse(SessionVideoStore.unfinishedTakes(referencedIDs: [id.uuidString])
            .contains { $0.id == id })
        XCTAssertFalse(SessionVideoStore.unfinishedTakes(referencedIDs: [])
            .contains { $0.id == id },
            "Even with every session gone, a deleted file cannot be listed — it is not on disk")
    }

    /// Retention is not consulted: this is the user deciding, like `discard`
    /// and `removeAll`, not the sweeper guessing.
    func testDeleteIgnoresTheRetentionWindow() throws {
        let id = UUID()
        let url = try writeStoredClip(id: id, daysAgo: 0)

        priceThenDelete(days: nil, referencedIDs: [id.uuidString])

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "A clip younger than the retention window must still go when explicitly asked")
    }

    func testDeleteNominatesNothingWhenNoClipIsOldEnough() throws {
        let id = UUID()
        let url = try writeStoredClip(id: id, daysAgo: 5)

        let removed = priceThenDelete(days: 30, referencedIDs: [id.uuidString])

        XCTAssertTrue(removed.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - The gate at the deletion site

    /// The trap, asserted at the only place it could actually spring.
    ///
    /// `VideoStorage` never nominates an unclaimed file, but the store must not
    /// be *relying* on that: a caller that hands over a hand-built selection, or
    /// one built before a session was deleted, must still not be able to destroy
    /// an unfinished take through this door. The claim check runs at the
    /// deletion site, against the live ids, so the name is refused here.
    func testASelectionNamingAnUnclaimedTakeDeletesNothing() throws {
        let take = UUID()
        let url = try writeStoredClip(id: take, daysAgo: 900)
        // Hand-built: exactly what `VideoStorage` would never produce.
        let forged = VideoStorage.Selection(cutoff: cutoff(days: nil),
                                            fileNames: ["\(take.uuidString).mov"],
                                            byteCount: 1_024)

        let removed = SessionVideoStore.deleteSessionClips(forged, referencedIDs: [])

        XCTAssertTrue(removed.isEmpty, "an unclaimed take was accepted for deletion")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "an unfinished take is a swim that only exists as video — "
                      + "no selection may reach it")
    }

    /// The stale-selection case: the screen priced two clips, then the session
    /// behind one of them was erased. The clip that lost its session is now an
    /// unclaimed file, so it drops out of the delete rather than being taken
    /// out from under the retention window that now owns it.
    func testAClipThatLostItsSessionAfterPricingIsNotDeleted() throws {
        let kept = UUID(), erased = UUID()
        let keptURL = try writeStoredClip(id: kept, daysAgo: 400)
        let erasedURL = try writeStoredClip(id: erased, daysAgo: 400)

        let priced = SessionVideoStore.storageSummary(
            referencedIDs: [kept.uuidString, erased.uuidString]).offer(for: cutoff(days: 90))
        XCTAssertEqual(priced.count, 2, "precondition: both were offered")

        // …and only one session survives to the moment of the delete.
        let removed = SessionVideoStore.deleteSessionClips(priced,
                                                           referencedIDs: [kept.uuidString])

        XCTAssertEqual(removed, ["\(kept.uuidString).mov"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: keptURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: erasedURL.path))
    }

    /// The mirror of the above: the delete may only ever *shrink* the offer.
    /// Nothing outside what the user was shown and agreed to can go, however
    /// the store has changed since.
    func testDeleteNeverRemovesAnythingOutsideThePricedSet() throws {
        let priced = UUID(), unpriced = UUID()
        let pricedURL = try writeStoredClip(id: priced, daysAgo: 400)
        let unpricedURL = try writeStoredClip(id: unpriced, daysAgo: 400)
        let referenced: Set<String> = [priced.uuidString, unpriced.uuidString]

        // An offer naming only one of the two claimed, old-enough clips.
        let offer = VideoStorage.Selection(cutoff: cutoff(days: 90),
                                           fileNames: ["\(priced.uuidString).mov"],
                                           byteCount: 1_024)
        let removed = SessionVideoStore.deleteSessionClips(offer, referencedIDs: referenced)

        XCTAssertEqual(removed, ["\(priced.uuidString).mov"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: pricedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unpricedURL.path),
                      "a clip the user was never shown must not be deleted alongside one they were")
    }

    /// An empty offer is a no-op, not a sweep. The control never reaches here
    /// with one — the button does not exist over an empty set — but the store
    /// must not turn "nothing selected" into "everything".
    func testAnEmptySelectionDeletesNothing() throws {
        let id = UUID()
        let url = try writeStoredClip(id: id, daysAgo: 900)
        let empty = VideoStorage.Selection(cutoff: cutoff(days: nil), fileNames: [], byteCount: 0)

        let removed = SessionVideoStore.deleteSessionClips(empty, referencedIDs: [id.uuidString])

        XCTAssertTrue(removed.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Sessions survive

    /// (a) the sessions still exist with their scores, (b) the clips are gone,
    /// (d) Results renders without a video section — `videoURL` is exactly what
    /// `ResultsView` branches on, and it has to be nil now.
    @MainActor
    func testSessionsKeepEverythingButTheirFootage() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SwimSession.self, configurations: config)
        let context = container.mainContext

        // The stored file is named after the result id — the invariant the
        // whole clip lifecycle rests on — so the fixture derives one from the
        // other rather than inventing a second id.
        var result = AnalysisResult.demo
        let id = result.id
        result.videoFileName = "\(id.uuidString).mp4"
        let url = try writeStoredClip(id: id, ext: "mp4", daysAgo: 400)
        let session = SwimSession(result: result)
        session.name = "Threshold Tuesday"
        session.notes = "Worked on high-elbow catch"
        context.insert(session)
        try context.save()

        let referenced = Set(try context.fetch(FetchDescriptor<SwimSession>()).map(\.id.uuidString))
        XCTAssertNotNil(session.decoded()?.videoURL, "precondition: the clip is playable")

        priceThenDelete(days: 90, referencedIDs: referenced)

        let fetched = try context.fetch(FetchDescriptor<SwimSession>())
        XCTAssertEqual(fetched.count, 1, "The session must survive its clip")
        let kept = try XCTUnwrap(fetched.first)
        XCTAssertEqual(kept.score, result.score)
        XCTAssertEqual(kept.grade, result.grade)
        XCTAssertEqual(kept.issueCount, result.issues.count)
        XCTAssertEqual(kept.issueNames, result.issues.map(\.name))
        XCTAssertEqual(kept.name, "Threshold Tuesday")
        XCTAssertEqual(kept.notes, "Worked on high-elbow catch")
        let decoded = try XCTUnwrap(kept.decoded())
        XCTAssertEqual(decoded.issues.count, result.issues.count)
        XCTAssertEqual(decoded.tips, result.tips)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(decoded.videoURL,
                     "Results renders its video section only when videoURL is non-nil")
    }

    /// Nothing here edits a session, so the referenced set is identical before
    /// and after — which is why no surviving file can change claim state.
    func testReferencedSetIsUnchangedByTheDelete() throws {
        let kept = UUID(), dropped = UUID()
        try writeStoredClip(id: kept, daysAgo: 1)
        try writeStoredClip(id: dropped, daysAgo: 400)
        let referenced: Set<String> = [kept.uuidString, dropped.uuidString]

        priceThenDelete(days: 90, referencedIDs: referenced)

        let after = SessionVideoStore.storageSummary(referencedIDs: referenced)
        XCTAssertTrue(after.offer(for: cutoff(days: nil)).fileNames
            .contains("\(kept.uuidString).mov"))
        XCTAssertFalse(after.offer(for: cutoff(days: nil)).fileNames
            .contains("\(dropped.uuidString).mov"))
    }
}
