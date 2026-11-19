import AppKit
import SwiftUI
import ServiceManagement

extension Notification.Name {
    static let windowRememberRestoreFailed = Notification.Name("WindowRemember.restoreFailed")
}

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
    private var restoreGeneration = 0
    private var topology = DisplayInfo.current.map { $0.id + NSStringFromRect($0.frame) }.joined()
    private let file: URL
    var savingPausedByFailure: Bool { learningProtected && restoreProblem != nil && !isRestoring }
    init(preview: Bool = false, storageURL: URL? = nil) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WindowRemember")
        file = storageURL ?? directory.appendingPathComponent("layouts.json")
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
        learningProtected = archive.protectedConfigurations?.contains(signature) == true || storageProblem != nil
        if archive.layouts[signature] != nil { scheduleRestore(reason: "App launched") }
        else { tick() }
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
        let capture = WindowAccess.capture(ignoring: [])
        let windows = capture.windows.map(\.record)
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        guard WindowPolicy.captureIsReady(expected: force ? [] : (archive.layouts[signature]?.windows ?? []), captured: windows, runningBundles: running, unreliableBundles: capture.unreliableBundles, invalidRoles: capture.invalidRoles) else {
            Diagnostics.log("learning.unreliable-capture", ["invalidRoles": capture.invalidRoles, "count": windows.count])
            return
        }
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
        restoreGeneration += 1
        settling?.cancel()
        if archive.layouts[signature] != nil { protect(true, configuration: signature) }
        else { learningProtected = false }
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
        guard WindowAccess.trusted else {
            failRestore("Accessibility access is unavailable. Enable access, then try again.", configuration: signature)
            return
        }
        guard !isRestoring else { status = "A restore is already in progress."; return }
        let configuration = signature
        let generation = restoreGeneration
        protect(true, configuration: configuration)
        isRestoring = true
        restoreTask = Task { @MainActor in
            defer { isRestoring = false; suspendedUntil = Date().addingTimeInterval(5) }
            var live: [LiveWindow] = []
            var ready = false
            // Wake/dock reconnects can briefly expose AXApplication objects as windows.
            // Recreate all AX references each time; never move those invalid objects.
            for attempt in 0..<4 {
                guard signature == configuration, generation == restoreGeneration else { return }
                let capture = WindowAccess.capture(ignoring: [], diagnostic: true)
                let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
                ready = WindowAccess.trusted && WindowPolicy.restoreCaptureIsReady(captured: capture.windows.map(\.record), invalidRoles: capture.invalidRoles)
                let missingBundles = Set(layout.windows.map(\.bundleID)).intersection(running).subtracting(capture.windows.map { $0.record.bundleID })
                Diagnostics.log("restore.capture-readiness", ["attempt": attempt + 1, "ready": ready, "invalidRoles": capture.invalidRoles, "count": capture.windows.count, "missingRunningBundles": Array(missingBundles).sorted(), "unreliableBundles": Array(capture.unreliableBundles).sorted()])
                if ready { live = capture.windows; break }
                if attempt < 3 { try? await Task.sleep(for: .seconds(Double(2 << attempt))) }
            }
            guard signature == configuration, generation == restoreGeneration else { return }
            guard ready else {
                failRestore("Window access has not settled after reconnecting. Try again when your displays are ready.", configuration: configuration)
                Diagnostics.log("restore.capture-unavailable", ["learningProtected": true, "configuration": configuration])
                return
            }
            Diagnostics.log("restore.begin", ["reason": reason, "layout": layout.name, "windows": layout.windows.map(Diagnostics.record)])
            var used = Set<Int>(); var moved = 0; var skipped = 0; var failed = 0
            var problems: [String] = []
            for saved in layout.windows {
                guard signature == configuration, generation == restoreGeneration else { Diagnostics.log("restore.interrupted", ["reason": "display changed"]); return }
                let candidates = live.indices.filter { !used.contains($0) && live[$0].record.bundleID == saved.bundleID }
                let candidateRecords = candidates.map { live[$0].record }
                guard let matchedOffset = WindowPolicy.match(saved, in: candidateRecords) else {
                    skipped += 1
                    if WindowPolicy.unmatchedIsFailure(saved, runningBundles: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))) {
                        failed += 1; problems.append(saved.appName + " · " + saved.title)
                    }
                    Diagnostics.log("restore.unmatched", ["window": Diagnostics.record(saved), "candidates": candidates.map { Diagnostics.record(live[$0].record) }]); continue
                }
                let index = candidates[matchedOffset]
                used.insert(index)
                Diagnostics.log("restore.match", ["saved": Diagnostics.record(saved), "live": Diagnostics.record(live[index].record), "strategy": saved.title == live[index].record.title ? "title" : "ordinal-or-app"])
                if await WindowAccess.restoreWindow(live[index].element, to: saved) { moved += 1 }
                else { skipped += 1; failed += 1; problems.append(saved.appName + " · " + saved.title) }
            }
            guard signature == configuration, generation == restoreGeneration else { return }
            protect(failed > 0, configuration: configuration)
            if failed > 0 {
                failRestore("Couldn’t restore \(failed) window\(failed == 1 ? "" : "s").\n" + problems.prefix(3).joined(separator: "\n"), configuration: configuration)
            } else { restoreProblem = nil }
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
        let capture = WindowAccess.capture(ignoring: [])
        guard !capture.invalidRoles, !capture.windows.isEmpty else {
            restoreProblem = "Window access is not ready. Your saved layout is kept."
            return
        }
        let windows = capture.windows.map(\.record)
        let previous = archive.layouts[signature]
        archive.layouts[signature] = Layout(id: previous?.id ?? UUID(), name: previous?.name ?? displays.map(\.name).joined(separator: " + "), configuration: signature, windows: windows)
        currentWindows = windows
        protect(false, configuration: signature)
        restoreProblem = nil
        persist()
    }
    func failRestore(_ message: String, configuration: String) {
        protect(true, configuration: configuration)
        guard configuration == signature else { return }
        restoreProblem = message
        isRestoring = false
        status = "Restore failed — layout saving is paused."
        Diagnostics.log("restore.error-shown", ["configuration": configuration, "savingPaused": true])
        NotificationCenter.default.post(name: .windowRememberRestoreFailed, object: self)
    }
    private func protect(_ value: Bool, configuration: String) {
        var protected = archive.protectedConfigurations ?? []
        let before = protected
        if value { protected.insert(configuration) } else { protected.remove(configuration) }
        archive.protectedConfigurations = protected
        if signature == configuration { learningProtected = value }
        if protected != before { persist() }
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
