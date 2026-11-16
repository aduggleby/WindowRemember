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
    @Published var learningProtected = false
    @Published var isRestoring = false
    private var restoreTask: Task<Void, Never>?
    private var topology = DisplayInfo.current.map { $0.id + NSStringFromRect($0.frame) }.joined()
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
        Diagnostics.log("app.started", ["trusted": trusted, "automatic": automatic, "displays": Diagnostics.displays()])
        tick()
    }
    func persist() {
        do { let data = try JSONEncoder().encode(archive); try data.write(to: file, options: .atomic) }
        catch { status = "Could not save: \(error.localizedDescription)"; Diagnostics.log("archive.save-failed", ["error": error.localizedDescription]) }
    }
    func tick() {
        let previousTrust = trusted
        trusted = WindowAccess.trusted
        if previousTrust != trusted { Diagnostics.log("permission.changed", ["trusted": trusted]) }
        if DisplayInfo.signature != signature || DisplayInfo.current.map({ $0.id + NSStringFromRect($0.frame) }).joined() != topology { displayChanged(); return }
        guard trusted, !paused, !isRestoring, Date() > suspendedUntil else { return }
        if learningProtected { return }
        learn()
    }
    func learn(force: Bool = false) {
        guard trusted, !isRestoring, (!learningProtected || force), (Date() > suspendedUntil || force), DisplayInfo.signature == signature else { return }
        let windows = WindowAccess.windows(ignoring: archive.ignoredApps, diagnostic: true).map(\.record)
        currentWindows = windows
        Diagnostics.log("learning.capture", ["configuration": signature, "pinned": archive.layouts[signature]?.pinned ?? false, "count": windows.count])
        guard !windows.isEmpty, force || archive.layouts[signature]?.pinned != true else { return }
        let previous = archive.layouts[signature]
        archive.layouts[signature] = Layout(id: previous?.id ?? UUID(), name: previous?.name ?? displays.map(\.name).joined(separator: " + "), configuration: signature, windows: windows, pinned: previous?.pinned ?? false)
        persist()
    }
    func displayChanged() {
        let nextTopology = DisplayInfo.current.map { $0.id + NSStringFromRect($0.frame) }.joined()
        guard DisplayInfo.signature != signature || nextTopology != topology else { return }
        Diagnostics.log("display.changed", ["previous": signature, "next": DisplayInfo.signature, "displays": Diagnostics.displays()])
        topology = nextTopology
        signature = DisplayInfo.signature
        displays = DisplayInfo.current
        scheduleRestore(reason: "Display setup changed")
    }
    func scheduleRestore(reason: String) {
        settling?.cancel()
        suspendedUntil = Date().addingTimeInterval(12)
        Diagnostics.log("restore.scheduled", ["reason": reason, "configuration": signature])
        settling = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, !paused, automatic else { Diagnostics.log("restore.cancelled", ["reason": "paused, disabled or superseded"]); return }
            if isRestoring { scheduleRestore(reason: reason); return }
            if let layout = archive.layouts[signature] { restore(layout, reason: reason) }
            else { learningProtected = false; status = "New display setup. Learning your layout."; Diagnostics.log("restore.no-saved-layout", ["configuration": signature]) }
        }
    }
    func saveScene(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trusted else { return }
        let windows = WindowAccess.windows(ignoring: archive.ignoredApps, diagnostic: true).map(\.record)
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
        guard !isRestoring else { status = "A restore is already in progress."; return }
        let configuration = signature
        isRestoring = true
        restoreTask = Task { @MainActor in
            defer { isRestoring = false; suspendedUntil = Date().addingTimeInterval(5) }
            let live = WindowAccess.windows(ignoring: archive.ignoredApps, diagnostic: true)
            if captureUndo {
                undoLayout = Layout(name: "Before restore", configuration: signature, windows: live.map(\.record))
                canUndo = true
            }
            Diagnostics.log("restore.begin", ["reason": reason, "layout": layout.name, "windows": layout.windows.map(Diagnostics.record)])
            var used = Set<Int>(); var moved = 0; var skipped = 0; var failed = 0
            for saved in layout.windows where !archive.ignoredApps.contains(saved.bundleID) {
                guard signature == configuration else { Diagnostics.log("restore.interrupted", ["reason": "display changed"]); return }
                let candidates = live.indices.filter { !used.contains($0) && live[$0].record.bundleID == saved.bundleID }
                let candidateRecords = candidates.map { live[$0].record }
                guard let matchedOffset = WindowPolicy.match(saved, in: candidateRecords) else {
                    skipped += 1
                    if !candidates.isEmpty { failed += 1 }
                    Diagnostics.log("restore.unmatched", ["window": Diagnostics.record(saved), "candidates": candidates.map { Diagnostics.record(live[$0].record) }]); continue
                }
                let index = candidates[matchedOffset]
                used.insert(index)
                Diagnostics.log("restore.match", ["saved": Diagnostics.record(saved), "live": Diagnostics.record(live[index].record), "strategy": saved.title == live[index].record.title ? "title" : "ordinal-or-app"])
                if await WindowAccess.restoreWindow(live[index].element, to: saved) { moved += 1 }
                else { skipped += 1; failed += 1 }
            }
            learningProtected = failed > 0
            currentWindows = WindowAccess.windows(ignoring: archive.ignoredApps).map(\.record)
            status = "Restored \(moved) windows" + (skipped > 0 ? " · \(skipped) unavailable" : " · All in place")
            if learningProtected { status += " · Saved layout protected; retry or resume learning in Settings." }
            Diagnostics.log("restore.complete", ["moved": moved, "skipped": skipped, "failed": failed, "learningProtected": learningProtected])
            archive.history.insert(RestoreEvent(reason: reason + " · " + layout.name, moved: moved, skipped: skipped), at: 0)
            archive.history = Array(archive.history.prefix(200)); persist()
        }
    }
    func captureDiagnostics() {
        Diagnostics.log("diagnostics.manual", ["trusted": WindowAccess.trusted, "paused": paused, "automatic": automatic, "restoring": isRestoring, "learningProtected": learningProtected, "configuration": signature, "displays": Diagnostics.displays()])
        _ = WindowAccess.windows(ignoring: archive.ignoredApps, diagnostic: true)
        status = "Diagnostic snapshot saved locally."
    }
    func undo() { guard !isRestoring, let layout = undoLayout else { return }; restore(layout, reason: "Undo", captureUndo: false); undoLayout = nil; canUndo = false }
    func togglePin(_ key: String) { archive.layouts[key]?.pinned.toggle(); persist() }
    func deleteScene(_ id: UUID) { archive.scenes.removeAll { $0.id == id }; persist() }
    func setIgnored(_ bundle: String, ignored: Bool) {
        archive.ignoredApps.removeAll { $0 == bundle }
        if ignored { archive.ignoredApps.append(bundle) }
        persist()
    }
}
