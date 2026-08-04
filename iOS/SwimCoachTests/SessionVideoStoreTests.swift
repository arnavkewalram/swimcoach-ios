import XCTest
@testable import SwimCoach

/// The clip lifecycle rests on one invariant: every file inside the session
/// store is named `<result-id>.<ext>`, so the orphan sweeper can decide what
/// to delete from `SwimSession.id` alone — without decoding `resultData`,
/// whose externally-stored keypoint blob costs a disk read plus a full JSON
/// pass per session at launch.
///
/// These tests pin both halves: the pure set-membership derivation, and the
/// store operations that have to keep producing names it can match.
final class SessionVideoStoreTests: XCTestCase {

    private var createdFiles: [URL] = []

    override func tearDown() {
        for url in createdFiles { try? FileManager.default.removeItem(at: url) }
        createdFiles = []
        super.tearDown()
    }

    /// A throwaway file in the temp directory, standing in for a capture.
    private func makeTempClip(ext: String = "mov") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try Data("fake-movie".utf8).write(to: url)
        createdFiles.append(url)
        return url
    }

    // MARK: - Orphan derivation (pure)

    func testFileNamedAfterASavedSessionSurvives() {
        let id = UUID()
        let orphans = SessionVideoStore.orphanedFileNames(
            among: ["\(id.uuidString).mov"], referencedIDs: [id.uuidString])
        XCTAssertTrue(orphans.isEmpty, "A saved session's own video must never be swept")
    }

    func testFileWithNoSessionIsOrphaned() {
        let stored = UUID().uuidString
        let orphans = SessionVideoStore.orphanedFileNames(
            among: ["\(stored).mov"], referencedIDs: [UUID().uuidString])
        XCTAssertEqual(orphans, ["\(stored).mov"])
    }

    func testMatchIgnoresTheExtension() {
        // `persist` keeps the source extension (mov from the camera, mp4 from
        // a photo import), so membership has to be decided on the basename.
        let id = UUID()
        for ext in ["mov", "mp4", "MOV", "m4v"] {
            let orphans = SessionVideoStore.orphanedFileNames(
                among: ["\(id.uuidString).\(ext)"], referencedIDs: [id.uuidString])
            XCTAssertTrue(orphans.isEmpty, "\(ext) file was swept despite a live session")
        }
    }

    func testEmptyStoreYieldsNoOrphans() {
        XCTAssertTrue(SessionVideoStore.orphanedFileNames(
            among: [], referencedIDs: [UUID().uuidString]).isEmpty)
    }

    func testEverySessionDeletedSweepsEverything() {
        let names = (0..<3).map { _ in "\(UUID().uuidString).mov" }
        XCTAssertEqual(
            Set(SessionVideoStore.orphanedFileNames(among: names, referencedIDs: [])),
            Set(names))
    }

    func testMixedDirectoryKeepsOnlyReferencedFiles() {
        let kept = UUID(), dropped = UUID()
        let orphans = SessionVideoStore.orphanedFileNames(
            among: ["\(kept.uuidString).mov", "\(dropped.uuidString).mp4"],
            referencedIDs: [kept.uuidString])
        XCTAssertEqual(orphans, ["\(dropped.uuidString).mp4"])
    }

    /// Nothing has ever written a non-id name into the store, so anything
    /// that isn't a session id is debris and should go.
    func testUnrecognizedNamesAreOrphaned() {
        let orphans = SessionVideoStore.orphanedFileNames(
            among: ["legacy-clip.mov", "swim_test.mp4", ".DS_Store"],
            referencedIDs: [UUID().uuidString])
        XCTAssertEqual(Set(orphans), ["legacy-clip.mov", "swim_test.mp4", ".DS_Store"])
    }

    /// `UUID.uuidString` is uppercase on both sides of the comparison; a
    /// case-folded match would be a false negative waiting to happen.
    func testMatchingIsCaseSensitive() {
        let id = UUID()
        let orphans = SessionVideoStore.orphanedFileNames(
            among: ["\(id.uuidString.lowercased()).mov"], referencedIDs: [id.uuidString])
        XCTAssertEqual(orphans.count, 1)
    }

    // MARK: - The invariant that makes the derivation safe

    func testAdoptedClipIsNamedAfterItsFutureResultID() throws {
        let clip = SessionVideoStore.adopt(try makeTempClip())
        createdFiles.append(clip.url)

        XCTAssertEqual(clip.url.deletingPathExtension().lastPathComponent, clip.id.uuidString)
        XCTAssertEqual(clip.url.deletingLastPathComponent().standardizedFileURL,
                       SessionVideoStore.directory.standardizedFileURL,
                       "adopt must move the capture out of temp and into the store")
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.url.path))
    }

    func testAdoptedClipSurvivesTheSweepOnceItsSessionExists() throws {
        let clip = SessionVideoStore.adopt(try makeTempClip())
        createdFiles.append(clip.url)

        // What the launch-time sweep sees: a directory listing vs the ids of
        // the saved sessions.
        XCTAssertTrue(SessionVideoStore.orphanedFileNames(
            among: [clip.url.lastPathComponent],
            referencedIDs: [clip.id.uuidString]).isEmpty)
    }

    func testAdoptMovesRatherThanCopies() throws {
        let source = try makeTempClip()
        let clip = SessionVideoStore.adopt(source)
        createdFiles.append(clip.url)

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path),
                       "The temp capture is the only copy — adopt must not leave a duplicate")
    }

    func testPersistingAnAlreadyAdoptedClipDoesNotCopyItAgain() throws {
        let clip = SessionVideoStore.adopt(try makeTempClip())
        createdFiles.append(clip.url)

        let name = SessionVideoStore.persist(clip.url, for: clip.id)

        XCTAssertEqual(name, clip.url.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.url.path))
        let stored = try FileManager.default.contentsOfDirectory(
            atPath: SessionVideoStore.directory.path)
        XCTAssertEqual(stored.filter { $0.hasPrefix(clip.id.uuidString) }.count, 1)
    }

    func testPersistingAnExternalClipNamesItAfterTheResultID() throws {
        let source = try makeTempClip(ext: "mp4")
        let id = UUID()

        let name = SessionVideoStore.persist(source, for: id)

        XCTAssertEqual(name, "\(id.uuidString).mp4")
        createdFiles.append(SessionVideoStore.directory.appendingPathComponent(name ?? ""))
        XCTAssertTrue(SessionVideoStore.orphanedFileNames(
            among: [name ?? ""], referencedIDs: [id.uuidString]).isEmpty)
    }

    /// Bundled demo videos are referenced by resource name and never copied,
    /// so they never appear in the swept directory at all.
    func testBundledVideoIsReferencedInPlaceAndStaysOutOfTheStore() throws {
        let bundled = try XCTUnwrap(
            Bundle.main.url(forResource: "swim_test", withExtension: "mp4"))
        let id = UUID()

        let name = SessionVideoStore.persist(bundled, for: id)

        XCTAssertEqual(name, "swim_test.mp4")
        let stored = try FileManager.default.contentsOfDirectory(
            atPath: SessionVideoStore.directory.path)
        XCTAssertFalse(stored.contains("swim_test.mp4"))
        XCTAssertFalse(stored.contains("\(id.uuidString).mp4"))
    }

    // MARK: - Discard

    func testDiscardRemovesAnAdoptedClip() throws {
        let clip = SessionVideoStore.adopt(try makeTempClip())

        SessionVideoStore.discard(clip)

        XCTAssertFalse(FileManager.default.fileExists(atPath: clip.url.path))
    }

    /// Retake on a clip the store never owned (bundled demo, photo import)
    /// must not reach outside the session directory.
    func testDiscardLeavesFilesTheStoreDoesNotOwn() throws {
        let external = try makeTempClip()

        SessionVideoStore.discard(PendingClip(external: external))

        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
    }

    func testExternalClipGetsItsOwnIDUpFront() throws {
        let a = PendingClip(external: try makeTempClip())
        let b = PendingClip(external: try makeTempClip())
        XCTAssertNotEqual(a.id, b.id)
    }
}
