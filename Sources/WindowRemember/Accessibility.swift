import AppKit
import ApplicationServices

struct LiveWindow {
    var element: AXUIElement
    var record: WindowRecord
}
struct WindowCapture {
    var windows: [LiveWindow] = []
    var unreliableBundles = Set<String>()
    var invalidRoles = false
}
enum WindowAccess {
    static var trusted: Bool { AXIsProcessTrusted() }
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard error == .success else {
            if error != .attributeUnsupported && error != .noValue { Diagnostics.log("ax.read-error", ["attribute": key, "error": error.rawValue]) }
            return nil
        }
        return value
    }
    static func windows(ignoring: [String], diagnostic: Bool = false) -> [LiveWindow] {
        capture(ignoring: ignoring, diagnostic: diagnostic).windows
    }
    static func capture(ignoring: [String], diagnostic: Bool = false) -> WindowCapture {
        guard trusted else { Diagnostics.log("capture.permission-denied"); return WindowCapture(invalidRoles: true) }
        let displays = DisplayInfo.current
        var report = WindowCapture()
        let onscreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let visibleOwners = Set(onscreen.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }.compactMap { $0[kCGWindowOwnerPID as String] as? Int32 })
        if diagnostic { Diagnostics.log("capture.onscreen", ["windows": onscreen.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }.map { ["owner": $0[kCGWindowOwnerName as String] ?? "", "pid": $0[kCGWindowOwnerPID as String] ?? 0, "bounds": $0[kCGWindowBounds as String] ?? [:]] }]) }
        // Remote sessions can be owned by an accessory helper rather than the main app.
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular || visibleOwners.contains(app.processIdentifier) {
            guard let bundle = app.bundleIdentifier, bundle != Bundle.main.bundleIdentifier, !ignoring.contains(bundle) else { continue }
            if diagnostic { Diagnostics.log("capture.app", ["bundle": bundle, "name": app.localizedName ?? "", "pid": app.processIdentifier, "activationPolicy": app.activationPolicy.rawValue]) }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.25)
            guard let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement] else {
                report.unreliableBundles.insert(bundle)
                if diagnostic { Diagnostics.log("capture.app-unavailable", ["bundle": bundle]) }; continue
            }
            var candidates = windows
            // Some apps expose a session only as their focused or main window.
            for key in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
                if let extra = attribute(element, key), CFGetTypeID(extra) == AXUIElementGetTypeID() {
                    let window = extra as! AXUIElement
                    if !candidates.contains(where: { CFEqual($0, window) }) { candidates.append(window) }
                }
            }
            for (index, window) in candidates.enumerated() {
                let title = attribute(window, kAXTitleAttribute) as? String ?? ""
                let role = attribute(window, kAXRoleAttribute) as? String ?? ""
                let subrole = attribute(window, kAXSubroleAttribute) as? String ?? ""
                if role == kAXApplicationRole || role.isEmpty {
                    report.invalidRoles = true
                    report.unreliableBundles.insert(bundle)
                }
                let minimized = (attribute(window, kAXMinimizedAttribute) as? Bool) == true
                let fullscreen = (attribute(window, "AXFullScreen") as? Bool) == true
                var positionSettable = DarwinBoolean(false)
                let settableError = AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &positionSettable)
                // Remote-desktop sessions can be AXUnknown subrole, despite being movable AXWindows.
                let eligibleRole = WindowPolicy.captures(role: role, subrole: subrole, minimized: false, fullscreen: fullscreen, positionSettable: positionSettable.boolValue)
                let reason = !eligibleRole ? "unsupported-role" : minimized ? "minimized" : "candidate"
                if diagnostic {
                    Diagnostics.log("capture.window", ["bundle": bundle, "title": title, "ordinal": index, "role": role, "subrole": subrole, "minimized": minimized, "fullscreen": fullscreen, "positionSettable": positionSettable.boolValue, "settableError": settableError.rawValue, "decision": reason])
                }
                guard eligibleRole, !minimized,
                      let p = attribute(window, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
                      let s = attribute(window, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else {
                    if diagnostic { Diagnostics.log("capture.excluded", ["bundle": bundle, "title": title, "reason": reason == "candidate" ? "geometry-unavailable" : reason]) }; continue
                }
                var point = CGPoint.zero; var size = CGSize.zero
                AXValueGetValue(p as! AXValue, .cgPoint, &point)
                AXValueGetValue(s as! AXValue, .cgSize, &size)
                guard size.width > 80, size.height > 60 else { if diagnostic { Diagnostics.log("capture.excluded", ["bundle": bundle, "title": title, "reason": "too-small"]) }; continue }
                let rect = CGRect(origin: point, size: size)
                guard let display = displays.max(by: { a,b in area(rect.intersection(a.frame)) < area(rect.intersection(b.frame)) }), area(rect.intersection(display.frame)) > 0 else { if diagnostic { Diagnostics.log("capture.excluded", ["bundle": bundle, "title": title, "reason": "off-display"]) }; continue }
                report.windows.append(LiveWindow(element: window, record: WindowRecord(bundleID: bundle, appName: app.localizedName ?? bundle, title: attribute(window, kAXTitleAttribute) as? String ?? "", ordinal: index, displayID: display.id, x: point.x - display.frame.minX, y: point.y - display.frame.minY, width: size.width, height: size.height, fullscreen: fullscreen)))
            }
        }
        if diagnostic { Diagnostics.log("capture.complete", ["windows": report.windows.map { Diagnostics.record($0.record) }, "displays": Diagnostics.displays()]) }
        return report
    }
    static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
    static func restoreWindow(_ window: AXUIElement, to record: WindowRecord) async -> Bool {
        guard let targetDisplay = DisplayInfo.current.first(where: { $0.id == record.displayID }) else { Diagnostics.log("restore.missing-display", Diagnostics.record(record)); return false }
        let wasFullscreen = (attribute(window, "AXFullScreen") as? Bool) == true
        if wasFullscreen, record.fullscreen == true, let current = frame(window),
           DisplayInfo.current.max(by: { area(current.intersection($0.frame)) < area(current.intersection($1.frame)) })?.id == targetDisplay.id {
            Diagnostics.log("restore.already-in-place", Diagnostics.record(record)); return true
        }
        if !wasFullscreen, record.fullscreen != true, frameMatches(window, record) {
            Diagnostics.log("restore.already-in-place", Diagnostics.record(record)); return true
        }
        if wasFullscreen {
            let error = AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse)
            Diagnostics.log("fullscreen.exit", ["window": Diagnostics.record(record), "error": error.rawValue])
            guard error == .success else { return false }
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled { return false }
                var settable = DarwinBoolean(false)
                _ = AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable)
                if (attribute(window, "AXFullScreen") as? Bool) != true && settable.boolValue { break }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard !Task.isCancelled else { return false }
        var landed = move(window, to: record)
        // Remote clients often resize asynchronously after receiving a frame request.
        for _ in 0..<3 {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return false }
            if frameMatches(window, record) { landed = true; break }
            landed = move(window, to: record)
        }
        if record.fullscreen == true || (wasFullscreen && !landed) {
            let error = AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanTrue)
            Diagnostics.log("fullscreen.enter", ["window": Diagnostics.record(record), "error": error.rawValue])
            guard error == .success else { return false }
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return false }
                if (attribute(window, "AXFullScreen") as? Bool) == true { break }
            }
            try? await Task.sleep(for: .milliseconds(500))
            guard let frame = frame(window), let display = DisplayInfo.current.first(where: { $0.id == record.displayID }) else { return false }
            let correctDisplay = DisplayInfo.current.max { area(frame.intersection($0.frame)) < area(frame.intersection($1.frame)) }?.id == display.id
            let success = landed && correctDisplay && (attribute(window, "AXFullScreen") as? Bool) == true
            Diagnostics.log("fullscreen.verified", ["window": Diagnostics.record(record), "actual": NSStringFromRect(frame), "success": success])
            return success
        }
        return landed && frameMatches(window, record)
    }
    static func frame(_ window: AXUIElement) -> CGRect? {
        guard let p = attribute(window, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = attribute(window, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point); AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }
    static func frameMatches(_ window: AXUIElement, _ record: WindowRecord) -> Bool {
        guard let frame = frame(window), let display = DisplayInfo.current.first(where: { $0.id == record.displayID }) else { return false }
        let width = min(record.width, display.visible.width), height = min(record.height, display.visible.height)
        let x = max(display.visible.minX, min(display.frame.minX + record.x, display.visible.maxX - width))
        let y = max(display.visible.minY, min(display.frame.minY + record.y, display.visible.maxY - height))
        return abs(frame.minX - x) < 5 && abs(frame.minY - y) < 5 && abs(frame.width - width) < 5 && abs(frame.height - height) < 5
    }
    static func move(_ window: AXUIElement, to record: WindowRecord) -> Bool {
        guard let display = DisplayInfo.current.first(where: { $0.id == record.displayID }) else { Diagnostics.log("move.missing-display", Diagnostics.record(record)); return false }
        var size = CGSize(width: min(record.width, display.visible.width), height: min(record.height, display.visible.height))
        var point = CGPoint(x: max(display.visible.minX, min(display.frame.minX + record.x, display.visible.maxX - size.width)), y: max(display.visible.minY, min(display.frame.minY + record.y, display.visible.maxY - size.height)))
        guard let sizeValue = AXValueCreate(.cgSize, &size), let pointValue = AXValueCreate(.cgPoint, &point) else { return false }
        let first = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let second = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pointValue)
        let third = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        Diagnostics.log("move.request", ["window": Diagnostics.record(record), "target": NSStringFromRect(CGRect(origin: point, size: size)), "sizeError": first.rawValue, "positionError": second.rawValue, "secondSizeError": third.rawValue])
        guard first == .success, second == .success,
              let actual = attribute(window, kAXPositionAttribute), CFGetTypeID(actual) == AXValueGetTypeID() else { return false }
        var landed = CGPoint.zero
        AXValueGetValue(actual as! AXValue, .cgPoint, &landed)
        guard let actualSize = attribute(window, kAXSizeAttribute), CFGetTypeID(actualSize) == AXValueGetTypeID() else { return false }
        var landedSize = CGSize.zero
        AXValueGetValue(actualSize as! AXValue, .cgSize, &landedSize)
        Diagnostics.log("move.observed", ["window": Diagnostics.record(record), "actual": NSStringFromRect(CGRect(origin: landed, size: landedSize))])
        return abs(landed.x - point.x) < 5 && abs(landed.y - point.y) < 5 && abs(landedSize.width - size.width) < 5 && abs(landedSize.height - size.height) < 5
    }
}
