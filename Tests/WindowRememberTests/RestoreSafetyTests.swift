import XCTest
@testable import WindowRemember

final class RestoreSafetyTests: XCTestCase {
    @MainActor func testFailurePausesSavingPersistsProtectionAndSignalsUser() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("layouts.json")
        let store = Store(preview: true, storageURL: file)
        let config = DisplayInfo.signature
        let target = Layout(name: "Test setup", configuration: config, windows: [record()])
        store.archive.layouts[config] = target
        var signaled = false
        let observer = NotificationCenter.default.addObserver(forName: .windowRememberRestoreFailed, object: store, queue: nil) { _ in signaled = true }
        defer { NotificationCenter.default.removeObserver(observer) }
        store.failRestore("A window could not be restored.", configuration: config)
        XCTAssertTrue(store.savingPausedByFailure)
        XCTAssertTrue(signaled)
        let saved = try Data(contentsOf: file)
        store.paused = false
        store.tick()
        XCTAssertEqual(try Data(contentsOf: file), saved)
        let reopened = try JSONDecoder().decode(Archive.self, from: saved)
        XCTAssertTrue(reopened.protectedConfigurations?.contains(config) == true)
        XCTAssertEqual(reopened.layouts[config]?.windows, target.windows)
    }

    private func record(_ bundle: String = "example.editor") -> WindowRecord {
        WindowRecord(bundleID: bundle, appName: "Editor", title: "Document", ordinal: 0, displayID: "external", x: 100, y: 100, width: 900, height: 600)
    }
    func testPartialRestoreProceedsWhenAnotherRunningAppHasNoWindows() {
        let available = [record()]
        XCTAssertTrue(WindowPolicy.restoreCaptureIsReady(captured: available, invalidRoles: false))
        XCTAssertTrue(WindowPolicy.captureIsReady(expected: available + [record("example.preview")], captured: available, runningBundles: ["example.editor", "example.preview"], unreliableBundles: [], invalidRoles: false))
        XCTAssertFalse(WindowPolicy.unmatchedIsFailure(record("example.preview"), unreliableBundles: []))
    }
    func testRestoreRetriesFailedQueriesAndInvalidWakeCaptures() {
        XCTAssertTrue(WindowPolicy.restoreCaptureIsReady(captured: [], invalidRoles: false))
        XCTAssertFalse(WindowPolicy.restoreCaptureIsReady(captured: [], invalidRoles: false, unreliableBundles: ["example.editor"]))
        XCTAssertFalse(WindowPolicy.restoreCaptureIsReady(captured: [record()], invalidRoles: true))
    }
    func testSuccessfulEmptyQueryMeansSavedWindowsAreClosed() {
        XCTAssertTrue(WindowPolicy.captureIsReady(expected: [record()], captured: [], runningBundles: ["example.editor"], unreliableBundles: [], invalidRoles: false))
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
    func testOnlyFailedQueriesMakeUnmatchedWindowsAnError() {
        XCTAssertTrue(WindowPolicy.unmatchedIsFailure(record(), unreliableBundles: ["example.editor"]))
        XCTAssertFalse(WindowPolicy.unmatchedIsFailure(record(), unreliableBundles: []))
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
