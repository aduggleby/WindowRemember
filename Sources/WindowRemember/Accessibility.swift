import AppKit
import ApplicationServices

struct LiveWindow {
    var element: AXUIElement
    var record: WindowRecord
}
enum WindowAccess {
    static var trusted: Bool { AXIsProcessTrusted() }
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }
    static func windows(ignoring: [String]) -> [LiveWindow] {
        guard trusted else { return [] }
        let displays = DisplayInfo.current
        var result: [LiveWindow] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundle = app.bundleIdentifier, bundle != Bundle.main.bundleIdentifier, !ignoring.contains(bundle) else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.25)
            guard let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for (index, window) in windows.enumerated() {
                guard (attribute(window, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole,
                      (attribute(window, kAXMinimizedAttribute) as? Bool) != true,
                      (attribute(window, "AXFullScreen") as? Bool) != true,
                      let p = attribute(window, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
                      let s = attribute(window, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { continue }
                var point = CGPoint.zero; var size = CGSize.zero
                AXValueGetValue(p as! AXValue, .cgPoint, &point)
                AXValueGetValue(s as! AXValue, .cgSize, &size)
                guard size.width > 80, size.height > 60 else { continue }
                let rect = CGRect(origin: point, size: size)
                guard let display = displays.max(by: { a,b in area(rect.intersection(a.frame)) < area(rect.intersection(b.frame)) }), area(rect.intersection(display.frame)) > 0 else { continue }
                result.append(LiveWindow(element: window, record: WindowRecord(bundleID: bundle, appName: app.localizedName ?? bundle, title: attribute(window, kAXTitleAttribute) as? String ?? "", ordinal: index, displayID: display.id, x: point.x - display.frame.minX, y: point.y - display.frame.minY, width: size.width, height: size.height)))
            }
        }
        return result
    }
    static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
    static func move(_ window: AXUIElement, to record: WindowRecord) -> Bool {
        guard let display = DisplayInfo.current.first(where: { $0.id == record.displayID }) else { return false }
        var size = CGSize(width: min(record.width, display.visible.width), height: min(record.height, display.visible.height))
        var point = CGPoint(x: max(display.visible.minX, min(display.frame.minX + record.x, display.visible.maxX - size.width)), y: max(display.visible.minY, min(display.frame.minY + record.y, display.visible.maxY - size.height)))
        guard let sizeValue = AXValueCreate(.cgSize, &size), let pointValue = AXValueCreate(.cgPoint, &point) else { return false }
        let first = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let second = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pointValue)
        _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        guard first == .success, second == .success,
              let actual = attribute(window, kAXPositionAttribute), CFGetTypeID(actual) == AXValueGetTypeID() else { return false }
        var landed = CGPoint.zero
        AXValueGetValue(actual as! AXValue, .cgPoint, &landed)
        guard let actualSize = attribute(window, kAXSizeAttribute), CFGetTypeID(actualSize) == AXValueGetTypeID() else { return false }
        var landedSize = CGSize.zero
        AXValueGetValue(actualSize as! AXValue, .cgSize, &landedSize)
        return abs(landed.x - point.x) < 5 && abs(landed.y - point.y) < 5 && abs(landedSize.width - size.width) < 5 && abs(landedSize.height - size.height) < 5
    }
}
