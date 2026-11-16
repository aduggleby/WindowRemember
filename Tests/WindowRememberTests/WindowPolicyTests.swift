import XCTest
@testable import WindowRemember

final class WindowPolicyTests: XCTestCase {
    func window(_ title: String, ordinal: Int = 0) -> WindowRecord {
        WindowRecord(bundleID: "com.microsoft.rdc.macos", appName: "Windows App", title: title, ordinal: ordinal, displayID: "monitor", x: 0, y: 0, width: 1000, height: 700)
    }
    func testFullScreenSessionIsCapturedDespitePositionBeingReadOnly() {
        XCTAssertTrue(WindowPolicy.captures(role: "AXWindow", subrole: "AXStandardWindow", minimized: false, fullscreen: true, positionSettable: false))
    }
    func testMovableUnknownWindowIsCapturedButDialogsAreNot() {
        XCTAssertTrue(WindowPolicy.captures(role: "AXWindow", subrole: "AXUnknown", minimized: false, fullscreen: false, positionSettable: true))
        XCTAssertFalse(WindowPolicy.captures(role: "AXWindow", subrole: "AXDialog", minimized: false, fullscreen: false, positionSettable: true))
        XCTAssertFalse(WindowPolicy.captures(role: "AXWindow", subrole: "AXUnknown", minimized: false, fullscreen: false, positionSettable: false))
    }
    func testMinimizedWindowIsExcluded() {
        XCTAssertFalse(WindowPolicy.captures(role: "AXWindow", subrole: "AXStandardWindow", minimized: true, fullscreen: false, positionSettable: true))
    }
    func testRemoteSessionDoesNotMatchConnectionBrowserWithSameOrdinal() {
        XCTAssertNil(WindowPolicy.match(window("remote-workstation.example"), in: [window("Windows App")]))
    }
    func testRemoteSessionMatchesTitleAfterWindowOrderChanges() {
        XCTAssertEqual(WindowPolicy.match(window("remote-workstation.example", ordinal: 1), in: [window("remote-workstation.example"), window("Windows App", ordinal: 1)]), 0)
    }
    func testOldLayoutsDecodeWithoutFullScreenField() throws {
        let data = try JSONEncoder().encode(window("Legacy"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "fullscreen")
        let restored = try JSONDecoder().decode(WindowRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(restored.fullscreen)
    }
}
