import AppKit
import SwiftUI
import ServiceManagement

@MainActor final class Store: ObservableObject {
    @Published var archive = Archive()
    @Published var trusted = WindowAccess.trusted
    @Published var paused = false
    @Published var status = "Your desk, remembered."
    @Published var displays = DisplayInfo.current
    @Published var currentWindows: [WindowRecord] = []
    @Published var restoreProblem: String?
    @Published var storageProblem: String?
    @Published var loginNeedsAttention = false
    private var signature = DisplayInfo.signature
    private var timer: Timer?
    private var settling: Task<Void, Never>?
    private var suspendedUntil = Date.distantPast
    @Published var learningProtected = false
    @Published var isRestoring = false
    private var restoreTask: Task<Void, Never>?
    private var topology = DisplayInfo.current.map { $0.id + NSStringFromRect($0.frame) }.joined()
    private let file: URL
    init(preview: Bool = false) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WindowRemember")
        file = directory.appendingPathComponent("layouts.json")
        if preview {
            trusted = true
            displays = [DisplayInfo(id: "sample-laptop", name: "MacBook", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visible: CGRect(x: 0, y: 25, width: 1440, height: 875)), DisplayInfo(id: "sample-external", name: "External display", frame: CGRect(x: 1440, y: 0, width: 2560, height: 1440), visible: CGRect(x: 1440, y: 25, width: 2560, height: 1415))]
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: file.path) { archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file)) }
        } catch { storageProblem = "Could not load saved layouts: \(error.localizedDescription)"; learningProtected = true }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.displayChanged() } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.scheduleRestore(reason: "Woke from sleep") } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.learn() } }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        Diagnostics.log("app.started", ["trusted": trusted,  "displays": Diagnostics.displays()])
        configureLogin()
        tick()
    }
    func persist() {
        do {
            let data = try JSONEncoder().encode(archive)
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            storageProblem = nil
        }
        catch { storageProblem = "Could not save: \(error.localizedDescription)"; Diagnostics.log("archive.save-failed", ["error": error.localizedDescription]) }
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
        guard trusted, storageProblem == nil, !isRestoring, (!learningProtected || force), (Date() > suspendedUntil || force), DisplayInfo.signature == signature else { return }
        let windows = WindowAccess.windows(ignoring: []).map(\.record)
        currentWindows = windows
        guard !windows.isEmpty else { return }
        let previous = archive.layouts[signature]
        if let previous, WindowPolicy.layoutsMatch(previous.windows, windows) { return }
        Diagnostics.log("learning.changed", ["configuration": signature, "windows": windows.map(Diagnostics.record)])
        archive.layouts[signature] = Layout(id: previous?.id ?? UUID(), name: previous?.name ?? displays.map(\.name).joined(separator: " + "), configuration: signature, windows: windows)
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
            guard !Task.isCancelled, !paused else { Diagnostics.log("restore.cancelled", ["reason": "paused or superseded"]); return }
            if isRestoring { scheduleRestore(reason: reason); return }
            if let layout = archive.layouts[signature] { restore(layout, reason: reason) }
            else { learningProtected = false; status = "New display setup. Learning your layout."; Diagnostics.log("restore.no-saved-layout", ["configuration": signature]) }
        }
    }
    func restoreCurrent() {
        guard let layout = archive.layouts[signature] else { status = "Arrange your windows first; a layout will be learned automatically."; return }
        restore(layout, reason: "Manual restore")
    }
    func restore(_ layout: Layout, reason: String) {
        guard WindowAccess.trusted else { WindowAccess.request(); return }
        guard !isRestoring else { status = "A restore is already in progress."; return }
        let configuration = signature
        isRestoring = true
        restoreTask = Task { @MainActor in
            defer { isRestoring = false; suspendedUntil = Date().addingTimeInterval(5) }
            let live = WindowAccess.windows(ignoring: [], diagnostic: true)
            Diagnostics.log("restore.begin", ["reason": reason, "layout": layout.name, "windows": layout.windows.map(Diagnostics.record)])
            var used = Set<Int>(); var moved = 0; var skipped = 0; var failed = 0
            var problems: [String] = []
            for saved in layout.windows {
                guard signature == configuration else { Diagnostics.log("restore.interrupted", ["reason": "display changed"]); return }
                let candidates = live.indices.filter { !used.contains($0) && live[$0].record.bundleID == saved.bundleID }
                let candidateRecords = candidates.map { live[$0].record }
                guard let matchedOffset = WindowPolicy.match(saved, in: candidateRecords) else {
                    skipped += 1
                    if !candidates.isEmpty { failed += 1; problems.append(saved.appName + " · " + saved.title) }
                    Diagnostics.log("restore.unmatched", ["window": Diagnostics.record(saved), "candidates": candidates.map { Diagnostics.record(live[$0].record) }]); continue
                }
                let index = candidates[matchedOffset]
                used.insert(index)
                Diagnostics.log("restore.match", ["saved": Diagnostics.record(saved), "live": Diagnostics.record(live[index].record), "strategy": saved.title == live[index].record.title ? "title" : "ordinal-or-app"])
                if await WindowAccess.restoreWindow(live[index].element, to: saved) { moved += 1 }
                else { skipped += 1; failed += 1; problems.append(saved.appName + " · " + saved.title) }
            }
            learningProtected = failed > 0
            restoreProblem = problems.isEmpty ? nil : problems.prefix(3).joined(separator: "\n")
            currentWindows = WindowAccess.windows(ignoring: []).map(\.record)
            status = "Restored \(moved) windows" + (skipped > 0 ? " · \(skipped) unavailable" : " · All in place")
            if learningProtected { status += " · Saved layout protected; retry from the menu bar." }
            Diagnostics.log("restore.complete", ["moved": moved, "skipped": skipped, "failed": failed, "learningProtected": learningProtected])
            persist()
        }
    }
    func captureDiagnostics() {
        Diagnostics.log("diagnostics.manual", ["trusted": WindowAccess.trusted, "paused": paused,  "restoring": isRestoring, "learningProtected": learningProtected, "configuration": signature, "displays": Diagnostics.displays()])
        _ = WindowAccess.windows(ignoring: [], diagnostic: true)
        Diagnostics.flush()
        status = "Diagnostic snapshot saved locally."
    }
    func adoptCurrentPositions() {
        guard !isRestoring else { return }
        learningProtected = false
        restoreProblem = nil
        learn(force: true)
    }
    private func configureLogin() {
        // Try once after installation. Respect a later user choice to disable login startup.
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { return }
        if !UserDefaults.standard.bool(forKey: "loginSetupAttempted") {
            UserDefaults.standard.set(true, forKey: "loginSetupAttempted")
            enableLogin()
        }
        loginNeedsAttention = SMAppService.mainApp.status == .requiresApproval
    }
    func enableLogin() {
        do {
            try SMAppService.mainApp.register()
            loginNeedsAttention = SMAppService.mainApp.status != .enabled
            if loginNeedsAttention { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            loginNeedsAttention = true
            Diagnostics.log("login.registration-failed", ["error": error.localizedDescription])
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
