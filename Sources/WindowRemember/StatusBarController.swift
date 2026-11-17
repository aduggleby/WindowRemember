import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = StatusBarController(store: Store())
        Diagnostics.log("lifecycle.launched", ["pid": ProcessInfo.processInfo.processIdentifier, "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"])
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showPopover()
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        Diagnostics.log("lifecycle.terminating", ["pid": ProcessInfo.processInfo.processIdentifier])
        Diagnostics.flush()
    }
}

@MainActor final class StatusBarController: NSObject {
    private let store: Store
    private let item: NSStatusItem
    private let popover = NSPopover()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    init(store: Store, item: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength), autosaveName: String = "WindowRemember.anchor") {
        self.store = store
        self.item = item
        super.init()
        item.autosaveName = autosaveName
        // A background utility must not disappear or quit when its popover closes.
        item.behavior = []
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuPanel().environmentObject(store))
        repair(reason: "launch")
        for name in [NSApplication.didChangeScreenParametersNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.repair(reason: "display-change") }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.repair(reason: "wake") }
        })
        timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.repair(reason: "heartbeat") }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func repair(reason: String) {
        let wasVisible = item.isVisible
        item.isVisible = true
        if let button = item.button {
            button.image = TrayIcon.image
            button.imagePosition = .imageOnly
            button.toolTip = "WindowRemember"
            button.setAccessibilityLabel("WindowRemember")
            button.target = self
            button.action = #selector(togglePopover)
        }
        Diagnostics.log("status-item.health", ["reason": reason, "wasVisible": wasVisible, "visible": item.isVisible, "buttonAvailable": item.button != nil, "frame": NSStringFromRect(item.button?.window?.frame ?? .zero), "popoverShown": popover.isShown, "pid": ProcessInfo.processInfo.processIdentifier])
    }
    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }
    func showPopover() {
        repair(reason: "open")
        guard let button = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
