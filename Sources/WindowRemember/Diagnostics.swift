import AppKit

/// Local, buffered JSON-lines diagnostics. Archives are never automatically deleted.
/// All diagnostics stay outside the app bundle and are never uploaded by the app.
struct DiagnosticLogWriter {
    let directory: URL
    var maximumFileSize = 5_000_000
    var file: URL { directory.appendingPathComponent("debug.jsonl") }

    func append(_ data: Data) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let attributes = try? manager.attributesOfItem(atPath: file.path),
           let size = attributes[.size] as? NSNumber, size.intValue >= maximumFileSize {
            let archives = directory.appendingPathComponent("Archive")
            try manager.createDirectory(at: archives, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            // UUID prevents overwrites even when rotating several times in one second.
            let destination = archives.appendingPathComponent("debug-\(stamp)-\(UUID().uuidString).jsonl")
            try manager.moveItem(at: file, to: destination)
        }
        if !manager.fileExists(atPath: file.path) {
            guard manager.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }
}

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
            if pending.count >= 65_536 || event.hasPrefix("restore.") || event.hasPrefix("lifecycle.") || event == "display.changed" || event == "learning.changed" { writePending() }
        }
    }
    static func flush() { queue.sync { writePending() } }
    private static func writePending() {
        guard !pending.isEmpty else { return }
        do {
            try DiagnosticLogWriter(directory: directory).append(pending)
            pending.removeAll(keepingCapacity: true)
        } catch {
            // Keep memory bounded even if the filesystem becomes unavailable.
            if pending.count > 1_048_576 { pending = pending.suffix(1_048_576) }
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
