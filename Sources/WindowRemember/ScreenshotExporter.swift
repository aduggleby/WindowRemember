import AppKit
import SwiftUI

/// Renders the actual app view with synthetic data, never a user's desktop or logs.
@MainActor enum ScreenshotExporter {
    static func export(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["remembering", "troubleshooting", "access-needed", "restore-failed"] {
            let store = Store(preview: true)
            store.trusted = name != "access-needed"
            if name == "restore-failed" {
                store.learningProtected = true
                store.restoreProblem = "Couldn’t restore one window. The app hasn’t made its window available yet."
            }
            let content = MenuPanel(expandedDiagnostics: name == "troubleshooting")
                .environmentObject(store)
                .preferredColorScheme(.light)
                .background(Color(nsColor: .windowBackgroundColor))
            let hosting = NSHostingView(rootView: content)
            let size = hosting.fittingSize
            hosting.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            guard let image = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                throw NSError(domain: "ScreenshotExporter", code: 1)
            }
            hosting.cacheDisplay(in: hosting.bounds, to: image)
            guard let png = image.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "ScreenshotExporter", code: 2)
            }
            try png.write(to: directory.appendingPathComponent(name + ".png"))
            window.orderOut(nil)
        }
    }
}
