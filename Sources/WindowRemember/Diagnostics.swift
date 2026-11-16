import AppKit

/// Local, bounded JSON-lines diagnostics. Never uploaded by the application.
enum Diagnostics {
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WindowRemember/Diagnostics")
    static let file = directory.appendingPathComponent("debug.jsonl")
    private static let lock = NSLock()
    static func log(_ event: String, _ fields: [String: Any] = [:]) {
        lock.lock(); defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 5_000_000 {
                let previous = directory.appendingPathComponent("debug.previous.jsonl")
                if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
                try FileManager.default.moveItem(at: file, to: previous)
            }
            var object = fields
            object["event"] = event
            object["time"] = ISO8601DateFormatter().string(from: Date())
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) + Data([10])
            if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: data)
        } catch { NSLog("WindowRemember diagnostics: %@", error.localizedDescription) }
    }
    static func record(_ window: WindowRecord) -> [String: Any] {
        ["app": window.appName, "bundle": window.bundleID, "title": window.title, "ordinal": window.ordinal, "fullscreen": window.fullscreen ?? false, "display": window.displayID, "frame": [window.x, window.y, window.width, window.height]]
    }
    static func displays() -> [[String: Any]] {
        DisplayInfo.current.map { ["id": $0.id, "name": $0.name, "frame": NSStringFromRect($0.frame), "visible": NSStringFromRect($0.visible)] }
    }
}
