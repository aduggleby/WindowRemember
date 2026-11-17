import AppKit
import XCTest
@testable import WindowRemember

final class StatusBarTests: XCTestCase {
    @MainActor func testHiddenStatusItemIsRestoredWithTemplateImageAndNoRemovalBehavior() {
        _ = NSApplication.shared
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let controller = StatusBarController(store: Store(preview: true), item: item, autosaveName: "WindowRemember.test")
        defer { NSStatusBar.system.removeStatusItem(item) }
        item.isVisible = false
        item.button?.image = nil
        controller.repair(reason: "test-display-change")
        XCTAssertTrue(item.isVisible)
        XCTAssertTrue(item.behavior.isEmpty)
        XCTAssertTrue(item.button?.image?.isTemplate == true)
        XCTAssertNotNil(item.button?.target)
        XCTAssertNotNil(item.button?.action)
    }
    @MainActor func testClosingLastWindowDoesNotTerminateBackgroundApp() {
        XCTAssertFalse(AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
