import XCTest
@testable import WindowRemember

final class RestoreSafetyTests: XCTestCase {
    private func record(_ bundle: String = "example.editor") -> WindowRecord {
        WindowRecord(bundleID: bundle, appName: "Editor", title: "Document", ordinal: 0, displayID: "external", x: 100, y: 100, width: 900, height: 600)
    }
    func testEmptyPostWakeCaptureCannotRestoreOrReleaseProtectionForRunningApps() {
        XCTAssertFalse(WindowPolicy.captureIsReady(expected: [record()], captured: [], runningBundles: ["example.editor"], unreliableBundles: [], invalidRoles: false))
    }
    func testApplicationObjectsReturnedAsWindowsRequireRetryEvenIfSomeWindowsAreValid() {
        XCTAssertFalse(WindowPolicy.captureIsReady(expected: [record()], captured: [record()], runningBundles: ["example.editor"], unreliableBundles: [], invalidRoles: true))
    }
    func testFailedAppQueryCannotBeTreatedAsClosedWindows() {
        XCTAssertFalse(WindowPolicy.captureIsReady(expected: [record()], captured: [record()], runningBundles: ["example.editor"], unreliableBundles: ["example.editor"], invalidRoles: false))
    }
    func testFreshCaptureBecomesReadyAfterTransientFailure() {
        XCTAssertTrue(WindowPolicy.captureIsReady(expected: [record()], captured: [record()], runningBundles: ["example.editor"], unreliableBundles: [], invalidRoles: false))
    }
    func testUnmatchedRunningAppIsFailureButClosedAppIsNot() {
        XCTAssertTrue(WindowPolicy.unmatchedIsFailure(record(), runningBundles: ["example.editor"]))
        XCTAssertFalse(WindowPolicy.unmatchedIsFailure(record(), runningBundles: []))
    }
    func testProtectionAndTargetFramesSurviveRestartRoundTrip() throws {
        var archive = Archive(layouts: ["setup": Layout(name: "Desk", configuration: "setup", windows: [record()])])
        archive.protectedConfigurations = ["setup"]
        let reopened = try JSONDecoder().decode(Archive.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(reopened.protectedConfigurations, ["setup"])
        XCTAssertEqual(reopened.layouts["setup"]?.windows, [record()])
    }
    func testClosedAppsDoNotPreventOtherWindowsRestoring() {
        XCTAssertTrue(WindowPolicy.captureIsReady(expected: [record(), record("example.closed")], captured: [record()], runningBundles: ["example.editor"], unreliableBundles: [], invalidRoles: false))
    }
}
