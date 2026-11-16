import AppKit
import SwiftUI

@MainActor final class Store: ObservableObject {
    @Published var archive = Archive()
    @Published var trusted = WindowAccess.trusted
    @Published var paused = false
    @Published var status = "Your desk, remembered."
    @Published var displays = DisplayInfo.current
    @Published var currentWindows: [WindowRecord] = []
    @Published var automatic = UserDefaults.standard.object(forKey: "automatic") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automatic, forKey: "automatic") }
    }
    private var signature = DisplayInfo.signature
    private var timer: Timer?
    private var settling: Task<Void, Never>?
    private var suspendedUntil = Date.distantPast
    private var undoLayout: Layout?
    @Published var canUndo = false
    private let file: URL
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WindowRemember")
        file = directory.appendingPathComponent("layouts.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) { archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file)) }
        } catch { status = "Could not load saved layouts: \(error.localizedDescription)" }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.displayChanged() } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.scheduleRestore(reason: "Woke from sleep") } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.learn() } }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        tick()
    }
    func persist() {
        do { let data = try JSONEncoder().encode(archive); try data.write(to: file, options: .atomic) }
        catch { status = "Could not save: \(error.localizedDescription)" }
    }
    func tick() {
        trusted = WindowAccess.trusted
        if DisplayInfo.signature != signature { displayChanged(); return }
        guard trusted, !paused, Date() > suspendedUntil else { return }
        learn()
    }
    func learn(force: Bool = false) {
        guard trusted, DisplayInfo.signature == signature else { return }
        let windows = WindowAccess.windows(ignoring: archive.ignoredApps).map(\.record)
        currentWindows = windows
        guard !windows.isEmpty, force || archive.layouts[signature]?.pinned != true else { return }
        let previous = archive.layouts[signature]
        archive.layouts[signature] = Layout(id: previous?.id ?? UUID(), name: previous?.name ?? displays.map(\.name).joined(separator: " + "), configuration: signature, windows: windows, pinned: previous?.pinned ?? false)
        persist()
    }
    func displayChanged() {
        guard DisplayInfo.signature != signature else { return }
        signature = DisplayInfo.signature
        displays = DisplayInfo.current
        scheduleRestore(reason: "Display setup changed")
    }
    func scheduleRestore(reason: String) {
        settling?.cancel()
        suspendedUntil = Date().addingTimeInterval(8)
        settling = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, !paused, automatic else { return }
            if let layout = archive.layouts[signature] { restore(layout, reason: reason) }
            else { status = "New display setup. Learning your layout." }
        }
    }
    func saveScene(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trusted else { return }
        let windows = WindowAccess.windows(ignoring: archive.ignoredApps).map(\.record)
        guard !windows.isEmpty else { status = "No accessible windows to save."; return }
        archive.scenes.append(Layout(name: trimmed, configuration: signature, windows: windows))
        persist(); status = "Saved \(trimmed)."
    }
    func restoreCurrent() {
        guard let layout = archive.layouts[signature] else { status = "Arrange your windows first; a layout will be learned automatically."; return }
        restore(layout, reason: "Manual restore")
    }
    func restore(_ layout: Layout, reason: String, captureUndo: Bool = true) {
        guard WindowAccess.trusted else { WindowAccess.request(); return }
        suspendedUntil = Date().addingTimeInterval(8)
        let live = WindowAccess.windows(ignoring: archive.ignoredApps)
        if captureUndo {
            undoLayout = Layout(name: "Before restore", configuration: signature, windows: live.map(\.record))
            canUndo = true
        }
        var used = Set<Int>(); var moved = 0; var skipped = 0
        for saved in layout.windows where !archive.ignoredApps.contains(saved.bundleID) {
            let candidates = live.indices.filter { !used.contains($0) && live[$0].record.bundleID == saved.bundleID }
            let match = candidates.first { !saved.title.isEmpty && live[$0].record.title == saved.title }
                ?? candidates.first { live[$0].record.ordinal == saved.ordinal }
                ?? candidates.first
            guard let index = match else { skipped += 1; continue }
            used.insert(index)
            if WindowAccess.move(live[index].element, to: saved) { moved += 1 } else { skipped += 1 }
        }
        status = "Restored \(moved) window\(moved == 1 ? "" : "s")" + (skipped > 0 ? " · \(skipped) unavailable" : " · All in place")
        archive.history.insert(RestoreEvent(reason: reason + " · " + layout.name, moved: moved, skipped: skipped), at: 0)
        archive.history = Array(archive.history.prefix(200)); persist()
    }
    func undo() { guard let layout = undoLayout else { return }; restore(layout, reason: "Undo", captureUndo: false); undoLayout = nil; canUndo = false }
    func togglePin(_ key: String) { archive.layouts[key]?.pinned.toggle(); persist() }
    func deleteScene(_ id: UUID) { archive.scenes.removeAll { $0.id == id }; persist() }
    func setIgnored(_ bundle: String, ignored: Bool) {
        archive.ignoredApps.removeAll { $0 == bundle }
        if ignored { archive.ignoredApps.append(bundle) }
        persist()
    }
}
