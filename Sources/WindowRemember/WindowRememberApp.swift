import SwiftUI
import AppKit

@main struct WindowRememberApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup("WindowRemember", id: "main") {
            Dashboard().environmentObject(store).frame(minWidth: 900, minHeight: 620)
        }.defaultSize(width: 1060, height: 740)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Restore Windows") { store.restoreCurrent() }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Undo Restore") { store.undo() }.disabled(!store.canUndo)
            }
        }
        MenuBarExtra("WindowRemember", systemImage: "rectangle.3.group") {
            MenuPanel().environmentObject(store)
        }.menuBarExtraStyle(.window)
    }
}
struct MenuPanel: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("WindowRemember", systemImage: "rectangle.3.group.fill").font(.headline)
            Text(store.status).font(.caption).foregroundStyle(.secondary)
            Button("Restore this setup", systemImage: "arrow.uturn.backward") { store.restoreCurrent() }.buttonStyle(.borderedProminent).disabled(!store.trusted)
            if !store.trusted { Button("Grant Accessibility access") { WindowAccess.request() } }
            ForEach(store.archive.scenes) { scene in Button(scene.name) { store.restore(scene, reason: "Scene") } }
            Divider()
            HStack {
                Button(store.paused ? "Resume" : "Pause") { store.paused.toggle() }
                Button("Open workspace") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            }
            Button("Quit WindowRemember") { NSApp.terminate(nil) }.font(.caption)
        }.padding(20).frame(width: 300)
    }
}
