import XCTest
@testable import SwimCoach

/// Guards the parts of the shipped bundle that App Review looks at and that
/// nothing else in the codebase can fail on.
///
/// These all read `Bundle.main`, which under a hosted unit-test target *is*
/// the app bundle — so this asserts on the real generated Info.plist rather
/// than on `project.yml`, and catches the case where someone edits the plist
/// directly and XcodeGen quietly reverts it on the next `xcodegen generate`.
///
/// The failure mode being guarded is uniform: none of this breaks the build,
/// none of it breaks at runtime, and you find out weeks later from a review
/// rejection or an upload that will not go through.
final class AppStoreConfigurationTests: XCTestCase {

    private func string(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    // MARK: - Export compliance

    /// Without this key App Store Connect asks for export-compliance answers
    /// on *every* upload, which blocks unattended TestFlight builds.
    func testDeclaresExportComplianceSoUploadsDoNotStall() {
        let value = Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption")

        XCTAssertNotNil(value, "ITSAppUsesNonExemptEncryption is missing — every upload will stop and ask")
        XCTAssertEqual(value as? Bool, false,
                       "the app makes no network calls and ships no cryptography of its own")
    }

    // MARK: - Purpose strings (Guideline 5.1.1)

    func testCameraPurposeStringExplainsWhatTheVideoIsFor() {
        let purpose = string("NSCameraUsageDescription")

        XCTAssertNotNil(purpose, "recording without a camera purpose string is an immediate rejection")
        XCTAssertTrue(purpose!.count >= 30,
                      "a purpose string has to say what the data is used for, not just name the sensor")
        XCTAssertTrue(purpose!.lowercased().contains("technique")
                        || purpose!.lowercased().contains("stroke"),
                      "should say the video is analyzed for technique")
    }

    func testMicrophonePurposeStringSaysWhatTheAudioIsUsedFor() {
        let purpose = string("NSMicrophoneUsageDescription")

        XCTAssertNotNil(purpose, "CameraManager adds a mic input, so this string is required")
        // The old string was "SwimCoach records audio alongside video." — that
        // says what is captured and nothing about why, which is the specific
        // thing 5.1.1 rejects.
        XCTAssertTrue(purpose!.count >= 60,
                      "must explain the use, not restate that audio is recorded")
    }

    /// Importing goes through SwiftUI's `.photosPicker`, which is out of
    /// process: the app receives only the chosen item and never touches
    /// `PHPhotoLibrary`. Declaring the permission would prompt for access the
    /// app cannot use, which is exactly what 5.1.1 tells you not to do.
    func testDoesNotAskForPhotoLibraryAccessItNeverUses() {
        XCTAssertNil(string("NSPhotoLibraryUsageDescription"),
                     "the picker is out-of-process; this permission is never exercised")
        XCTAssertNil(string("NSPhotoLibraryAddUsageDescription"),
                     "nothing is written back to the library — exports go through ShareLink")
    }

    /// Permissions the app has no code path for. Each one is a prompt the user
    /// cannot explain and a reviewer will ask about.
    func testDeclaresNoPermissionsTheAppDoesNotUse() {
        for key in ["NSLocationWhenInUseUsageDescription",
                    "NSLocationAlwaysAndWhenInUseUsageDescription",
                    "NSContactsUsageDescription",
                    "NSHealthShareUsageDescription",
                    "NSHealthUpdateUsageDescription",
                    "NSBluetoothAlwaysUsageDescription",
                    "NSUserTrackingUsageDescription"] {
            XCTAssertNil(string(key), "\(key) is declared but nothing in the app uses it")
        }
    }

    // MARK: - Privacy manifest

    func testPrivacyManifestShipsInTheBundle() {
        XCTAssertNotNil(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
                        "required for App Store submission since May 2024")
    }

    func testPrivacyManifestStillClaimsNoTrackingAndNoCollection() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try XCTUnwrap(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: url), format: nil) as? [String: Any])

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [Any])?.count, 0)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0,
                       "if the app ever collects anything this must be declared, and the App Store Connect privacy label updated to match")
    }

    /// Every required-reason API the app touches needs a declared reason code.
    /// `@AppStorage` is UserDefaults (CA92.1) and the video store reads file
    /// timestamps (C617.1).
    func testPrivacyManifestDeclaresTheRequiredReasonAPIsInUse() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try XCTUnwrap(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: url), format: nil) as? [String: Any])
        let declared = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])

        let byType = Dictionary(uniqueKeysWithValues: declared.compactMap { entry -> (String, [String])? in
            guard let type = entry["NSPrivacyAccessedAPIType"] as? String,
                  let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] else { return nil }
            return (type, reasons)
        })

        XCTAssertEqual(byType["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])
        XCTAssertEqual(byType["NSPrivacyAccessedAPICategoryFileTimestamp"], ["C617.1"])
    }

    // MARK: - Bundle shape

    func testVersionKeysResolveToRealValues() {
        // Regression: XcodeGen's generated plist hardcoded 1.0/1 until the
        // build settings were mapped through (d13f51b).
        let short = string("CFBundleShortVersionString")
        let build = string("CFBundleVersion")

        XCTAssertNotNil(short)
        XCTAssertNotEqual(short, "1.0", "marketing version did not come through from build settings")
        XCTAssertNotNil(build)
        XCTAssertFalse(short!.hasPrefix("$("), "build setting was not substituted")
        XCTAssertFalse(build!.hasPrefix("$("), "build setting was not substituted")
    }

    func testLaunchScreenIsDeclared() {
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen"),
                        "an app without a launch screen gets letterboxed and rejected under 2.1")
    }

    /// The app is iPhone-only (`TARGETED_DEVICE_FAMILY: "1"`) and portrait
    /// only. If iPad support is ever added, iPad orientation keys have to come
    /// with it or review will file it as a broken iPad layout.
    func testOrientationDeclarationMatchesTheDeviceFamily() {
        let iPhone = Bundle.main.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations~iphone") as? [String]

        XCTAssertEqual(iPhone, ["UIInterfaceOrientationPortrait"])
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations~ipad"),
                     "iPad orientations declared for an iPhone-only target — one of the two is wrong")
    }

    /// Users' swim videos live in Documents. Exposing that over Files/iTunes
    /// would put private footage a tap away for anyone with the phone.
    func testUsersVideosAreNotExposedOverFileSharing() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool, false)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool, false)
    }
}
