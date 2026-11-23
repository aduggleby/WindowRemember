import AppKit

/// Local, bounded, buffered JSON-lines diagnostics. Never uploaded by the app.
enum Diagnostics {
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WindowRemember/Diagnostics")
    static let file = directory.appendingPathComponent("debug.jsonl")
    private static let queue = DispatchQueue(label: "WindowRemember.Diagnostics", qos: .utility)
    private static var pending = Data()
    private static let timer: DispatchSourceTimer = {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { writePending() }
        timer.resume()
        return timer
    }()
    static func log(_ event: String, _ fields: [String: Any] = [:]) {
        var object = fields
        object["event"] = event
        object["time"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        _ = timer
        queue.async {
            pending.append(data)
            pending.append(10)
            if pending.count >= 65_536 { writePending() }
        }
    }
    static func flush() { queue.sync { writePending() } }
    private static func writePending() {
        guard !pending.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // Read fresh filesystem attributes: URL resource values can retain the old
            // pre-rotation size and otherwise rotate every subsequent write.
            if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
               let size = attributes[.size] as? NSNumber, size.intValue > 5_000_000 {
                let previous = directory.appendingPathComponent("debug.previous.jsonl")
                if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
                try FileManager.default.moveItem(at: file, to: previous)
            }
            if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: pending)
            pending.removeAll(keepingCapacity: true)
        } catch {
            // Keep memory bounded even if the filesystem becomes unavailable.
            pending.removeAll(keepingCapacity: true)
            NSLog("WindowRemember diagnostics: %@", error.localizedDescription)
        }
    }
    static func record(_ window: WindowRecord) -> [String: Any] {
        ["app": window.appName, "bundle": window.bundleID, "title": window.title, "ordinal": window.ordinal, "fullscreen": window.fullscreen ?? false, "display": window.displayID, "frame": [window.x, window.y, window.width, window.height]]
    }
    static func displays() -> [[String: Any]] {
        DisplayInfo.current.map { ["id": $0.id, "name": $0.name, "frame": NSStringFromRect($0.frame), "visible": NSStringFromRect($0.visible)] }
    }
}
