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
///     that ever stopped recognising a bundled sample, three strangers' swims
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
            XCTAssertFalse(clip.work.isEmpty, "\(clip.fileName) names no source work")
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
        // Whole phrases, not tokens. Splitting "stroke_asymmetry" on the
        // underscore forbids the word "stroke" everywhere — and "stroke",
        // "body", "kick" and "rate" are ordinary swimming vocabulary. The
        // app's own camera purpose string says "analyze your stroke
        // technique". What must not appear next to an unanalyzed clip is the
        // finding itself: "body sag", "stroke asymmetry".
        let faultPhrases = FeedbackEngine.issueNames
            .map { $0.replacingOccurrences(of: "_", with: " ").lowercased() }
        for clip in SampleClipCatalog.all {
            let copy = "\(clip.title) \(clip.vantage) \(clip.footage)".lowercased()
            for phrase in faultPhrases {
                XCTAssertFalse(copy.contains(phrase),
                               "\(clip.fileName) names the fault '\(phrase)' in copy the app has not measured")
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
    /// when it happens to be called `sample_crawl_deck.mp4`.
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
        XCTAssertEqual(credit.author, "It is a wonderful world")
        XCTAssertEqual(credit.work, "Front Crawl Above Water, Front Crawl Underwater and Sprint Front Crawl Underwater")
        XCTAssertEqual(credit.licenseShortName, "CC BY-SA 4.0")
        XCTAssertEqual(credit.licenseURL.absoluteString,
                       "https://creativecommons.org/licenses/by-sa/4.0")

        // The rendered sentence is what actually discharges CC BY-SA 4.0 §3(a),
        // so assert on it rather than on the parts alone.
        let line = credit.creditLine
        XCTAssertTrue(line.contains(credit.author), "credit line drops the author")
        XCTAssertTrue(line.contains(credit.work), "credit line drops the work")
        XCTAssertTrue(line.contains(credit.licenseName), "credit line drops the licence")
    }

    func testLicenceURLIsHTTPS() {
        XCTAssertEqual(SampleClipCatalog.attribution.licenseURL.scheme, "https")
    }

    // MARK: - Source pages (§3(a)(1)(A)(v): link the material, not just the licence)

    func testEveryClipLinksAnHTTPSCommonsFilePage() {
        for clip in SampleClipCatalog.all {
            let url = clip.sourceURL
            XCTAssertEqual(url.scheme, "https", "\(clip.fileName) links its source over plain HTTP")
            XCTAssertEqual(url.host, "commons.wikimedia.org",
                           "\(clip.fileName) links somewhere other than Wikimedia Commons")
            XCTAssertTrue(url.path.hasPrefix("/wiki/File:"),
                          "\(clip.fileName) links a Commons page that is not a file page: \(url.path)")
        }
    }

    func testEveryClipLinksADistinctSourcePage() {
        let urls = SampleClipCatalog.all.map(\.sourceURL)
        XCTAssertEqual(Set(urls).count, urls.count,
                       "two clips link the same Commons file, so one clip's source is uncredited")
    }

    /// Distinctness cannot catch two links swapped between rows, and a
    /// swapped pair would label one file with another's title. So pin the
    /// mapping — clip to the Commons file it was cut from — the same way the
    /// attribution test pins the author.
    func testEachClipLinksTheCommonsFileItWasCutFrom() {
        let expected = [
            "sample_crawl_deck.mp4":
                "https://commons.wikimedia.org/wiki/File:Front_Crawl_Above_Water.webm",
            "sample_crawl_underwater.mp4":
                "https://commons.wikimedia.org/wiki/File:Front_Crawl_Underwater.webm",
            "sample_crawl_sprint.mp4":
                "https://commons.wikimedia.org/wiki/File:Sprint_Front_Crawl_Underwater.webm",
        ]
        XCTAssertEqual(Set(SampleClipCatalog.all.map(\.fileName)), Set(expected.keys),
                       "the catalog changed; pin the new clip's source page here")
        for clip in SampleClipCatalog.all {
            XCTAssertEqual(clip.sourceURL.absoluteString, expected[clip.fileName],
                           "\(clip.fileName) links the wrong Commons file")

            // The link is labelled with `work`, so the page it opens has to
            // be the file of that name — Commons titles are the work with
            // spaces as underscores.
            let fileTitle = clip.work.replacingOccurrences(of: " ", with: "_")
            XCTAssertEqual(clip.sourceURL.lastPathComponent, "File:\(fileTitle).webm",
                           "\(clip.fileName)'s source link is labelled '\(clip.work)' but opens another file")
        }
    }

    /// The credit line and the source links are two halves of one notice. A
    /// clip whose work has a link but no mention in the sentence is credited
    /// by a bare URL, which is not what the licence asked for.
    func testTheCreditLineNamesEveryLinkedWork() {
        let line = SampleClipCatalog.attribution.creditLine
        let works = SampleClipCatalog.all.map(\.work)
        for clip in SampleClipCatalog.all {
            // "Front Crawl Underwater" sits inside "Sprint Front Crawl
            // Underwater", so a plain `contains` would pass with the shorter
            // title dropped. Strike the longer titles out first, so what is
            // left can only match the work named in its own right.
            let enclosing = works.filter { $0 != clip.work && $0.contains(clip.work) }
            let remainder = enclosing.reduce(line) {
                $0.replacingOccurrences(of: $1, with: "")
            }
            XCTAssertTrue(remainder.contains(clip.work),
                          "the credit line never names '\(clip.work)', the work \(clip.fileName) links to")
        }
    }
}
