import AppKit

/// A template anchor that remains available without relying on an SF Symbol name.
enum TrayIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: 7, y: 12, width: 4, height: 4))
            ring.lineWidth = 1.5
            ring.stroke()
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: 9, y: 12))
            path.line(to: NSPoint(x: 9, y: 2))
            path.move(to: NSPoint(x: 6, y: 10))
            path.line(to: NSPoint(x: 12, y: 10))
            path.move(to: NSPoint(x: 2, y: 7))
            path.curve(to: NSPoint(x: 9, y: 2), controlPoint1: NSPoint(x: 2, y: 3), controlPoint2: NSPoint(x: 5, y: 2))
            path.curve(to: NSPoint(x: 16, y: 7), controlPoint1: NSPoint(x: 13, y: 2), controlPoint2: NSPoint(x: 16, y: 3))
            path.move(to: NSPoint(x: 1, y: 5))
            path.line(to: NSPoint(x: 2, y: 7))
            path.line(to: NSPoint(x: 4, y: 6))
            path.move(to: NSPoint(x: 14, y: 6))
            path.line(to: NSPoint(x: 16, y: 7))
            path.line(to: NSPoint(x: 17, y: 5))
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "WindowRemember"
        return image
    }()
}
