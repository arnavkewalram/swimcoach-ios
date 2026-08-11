import XCTest
import AVFoundation
@testable import SwimCoach

/// Guards the sample-swim catalog and, more importantly, the two things about
/// it that fail *silently* in a shipped build:
///
///  1. **A row whose file did not ship.** A typo in `fileName`, or a clip
///     dropped without the matching `project.yml` resources entry, produces a
///     row that looks completely normal and does nothing when tapped. Nothing
///     in the type system catches it, so it is caught here — against
///     `Bundle.main`, which under a hosted unit-test target *is* the app
///     bundle, so this asserts on the real product rather than on a fixture.
///
///  2. **The no-save rule losing its grip.** `AnalyzingView` decides whether
///     to write a `SwimSession` by asking `SampleClipCatalog.isSample`. If
///     that ever stopped recognising a bundled sample, four strangers' swims
///     would start landing in the user's history, trends and streaks — and
///     the app would look entirely correct while doing it.
final class SampleClipCatalogTests: XCTestCase {

    // MARK: - Catalog shape

    func testCatalogIsNotEmpty() {
        XCTAssertFalse(SampleClipCatalog.all.isEmpty,
                       "the samples screen has nothing to list")
    }

    func testEveryClipHasAUniqueFileName() {
        let names = SampleClipCatalog.all.map(\.fileName)
        XCTAssertEqual(Set(names).count, names.count,
                       "two catalog rows name the same file, so one shadows the other")
    }

    func testEveryClipCarriesCopyForEveryField() {
        for clip in SampleClipCatalog.all {
            XCTAssertFalse(clip.title.isEmpty, "\(clip.fileName) has no title")
            XCTAssertFalse(clip.vantage.isEmpty, "\(clip.fileName) has no vantage")
            XCTAssertFalse(clip.footage.isEmpty, "\(clip.fileName) has no description")
            XCTAssertFalse(clip.resourceName.isEmpty, "\(clip.fileName) has no resource name")
            XCTAssertEqual(clip.resourceExtension, "mp4",
                           "\(clip.fileName) is not the container the pipeline expects")
        }
    }

    /// The row copy must describe the footage, never the findings — see the
    /// catalog's header note and `VerdictChip`'s. This cannot check intent,
    /// but it can check that no fault the app can actually detect has been
    /// pre-announced next to a clip nobody has analyzed yet.
    func testNoRowPreAnnouncesAFault() {
        let faultWords = FeedbackEngine.issueNames
            .flatMap { $0.split(separator: "_").map(String.init) }
            .filter { $0.count > 3 }
        for clip in SampleClipCatalog.all {
            let copy = "\(clip.title) \(clip.vantage) \(clip.footage)".lowercased()
            for word in faultWords {
                XCTAssertFalse(copy.contains(word),
                               "\(clip.fileName) names the fault term '\(word)' in copy the app has not measured")
            }
        }
    }

    // MARK: - Bundle resolution (the silent shipping failure)

    func testEveryListedClipActuallyShippedInTheBundle() {
        for clip in SampleClipCatalog.all {
            XCTAssertNotNil(
                clip.bundleURL(),
                """
                \(clip.fileName) is listed in SampleClipCatalog but is not in the \
                app bundle. Either the file name is wrong or Resources/SampleClips \
                is missing from project.yml — the row would ship dead.
                """)
        }
    }

    func testEveryShippedClipIsAReadableVideo() async throws {
        for clip in SampleClipCatalog.all {
            let url = try XCTUnwrap(clip.bundleURL(), "\(clip.fileName) did not ship")
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            XCTAssertFalse(tracks.isEmpty,
                           "\(clip.fileName) shipped but carries no video track")
            let duration = try await asset.load(.duration).seconds
            XCTAssertGreaterThan(duration, 3.0,
                                 "\(clip.fileName) is shorter than one 3-second SwimTCN window")
        }
    }

    // MARK: - The sample seam

    func testABundledSampleIsRecognisedAsASample() throws {
        for clip in SampleClipCatalog.all {
            let url = try XCTUnwrap(clip.bundleURL())
            XCTAssertEqual(SampleClipCatalog.sample(for: url), clip)
            XCTAssertTrue(SampleClipCatalog.isSample(url))
        }
    }

    /// The reason the seam is an identity check and not a filename match: a
    /// swim the user filmed must get real analysis and a saved session even
    /// when it happens to be called `sample_poolside.mp4`.
    func testAUserFileSharingASampleNameIsNotASample() throws {
        let clip = try XCTUnwrap(SampleClipCatalog.all.first)
        let impostor = SessionVideoStore.directory
            .appendingPathComponent(clip.fileName)
        XCTAssertNil(SampleClipCatalog.sample(for: impostor))
        XCTAssertFalse(SampleClipCatalog.isSample(impostor),
                       "a user's own clip would be silently dropped from their history")
    }

    func testTheBundledDemoCartoonIsNotASample() throws {
        let demo = try XCTUnwrap(
            Bundle.main.url(forResource: "swim_test", withExtension: "mp4"))
        XCTAssertFalse(SampleClipCatalog.isSample(demo),
                       "the synthetic demo clip is not sample footage and keeps its own path")
    }

    func testUnrelatedFootageIsNotASample() {
        let filmed = SessionVideoStore.directory
            .appendingPathComponent("\(UUID().uuidString).mov")
        XCTAssertNil(SampleClipCatalog.sample(for: filmed))
        XCTAssertFalse(SampleClipCatalog.isSample(filmed))
    }

    /// A sample must cost the session store nothing: `persist` has to
    /// recognise the bundled source and hand back its resource name instead
    /// of copying 1.5 MB of somebody else's swim into the user's Documents on
    /// every tap. This is the property the flat-bundle resources entry in
    /// project.yml exists to hold.
    func testPersistingASampleReferencesTheBundleInsteadOfCopying() throws {
        for clip in SampleClipCatalog.all {
            let url = try XCTUnwrap(clip.bundleURL())
            let id = UUID()
            let name = SessionVideoStore.persist(url, for: id)
            XCTAssertEqual(name, clip.fileName,
                           "\(clip.fileName) was not recognised as a bundled resource")
            let copied = SessionVideoStore.directory
                .appendingPathComponent("\(id.uuidString).mp4")
            XCTAssertFalse(FileManager.default.fileExists(atPath: copied.path),
                           "\(clip.fileName) was copied into the session store")
        }
    }

    /// Round trip: what analysis stores in `videoFileName` must resolve back
    /// to a playable URL, or Results shows a sample it cannot play.
    func testAPersistedSampleNameResolvesBackToAPlayableURL() throws {
        for clip in SampleClipCatalog.all {
            let resolved = SessionVideoStore.url(forFileName: clip.fileName)
            XCTAssertEqual(resolved, clip.bundleURL(),
                           "\(clip.fileName) does not resolve back out of the bundle")
        }
    }

    // MARK: - Attribution (a licence condition, not a nicety)

    func testAttributionNamesTheAuthorTheWorkAndTheLicence() {
        let credit = SampleClipCatalog.attribution
        XCTAssertEqual(credit.author, "koolkatkari")
        XCTAssertEqual(credit.work, "Mary's Swim Boot Camp")
        XCTAssertEqual(credit.licenseShortName, "CC BY 3.0")
        XCTAssertEqual(credit.licenseURL.absoluteString,
                       "https://creativecommons.org/licenses/by/3.0")

        // The rendered sentence is what actually discharges CC BY 3.0 §4(c),
        // so assert on it rather than on the parts alone.
        let line = credit.creditLine
        XCTAssertTrue(line.contains(credit.author), "credit line drops the author")
        XCTAssertTrue(line.contains(credit.work), "credit line drops the work")
        XCTAssertTrue(line.contains(credit.licenseName), "credit line drops the licence")
    }

    func testLicenceURLIsHTTPS() {
        XCTAssertEqual(SampleClipCatalog.attribution.licenseURL.scheme, "https")
    }
}
