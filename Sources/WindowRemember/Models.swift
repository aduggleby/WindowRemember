import AppKit

struct WindowRecord: Codable, Identifiable, Equatable {
    var id: String { "\(bundleID):\(title):\(ordinal)" }
    var bundleID: String
    var appName: String
    var title: String
    var ordinal: Int
    var displayID: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var fullscreen: Bool? = nil
}
struct Layout: Codable, Identifiable {
    var id = UUID()
    var name: String
    var configuration: String
    var windows: [WindowRecord]
    var updated = Date()
}
// Unknown legacy keys (scenes, pins, history, exclusions) are deliberately ignored.
struct Archive: Codable {
    var layouts: [String: Layout] = [:]
}
struct DisplayInfo: Identifiable {
    var id: String
    var name: String
    var frame: CGRect
    var visible: CGRect
    static var current: [DisplayInfo] {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value).takeRetainedValue()
            let identity = CFUUIDCreateString(nil, uuid)! as String
            func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height) }
            return DisplayInfo(id: identity, name: screen.localizedName, frame: flip(screen.frame), visible: flip(screen.visibleFrame))
        }
    }
    static var signature: String { current.map(\.id).sorted().joined(separator: "|") }
}
