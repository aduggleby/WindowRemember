import SwiftUI
import AppKit

@main struct WindowRememberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    init() {
        if let flag = CommandLine.arguments.firstIndex(of: "--render-screenshots"), CommandLine.arguments.indices.contains(flag + 1) {
            do { try ScreenshotExporter.export(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1])) }
            catch { fputs("Screenshot export failed: \(error.localizedDescription)\n", stderr); exit(1) }
            exit(0)
        }
    }
    var body: some Scene {
        Settings { EmptyView() }
    }
}

struct MenuPanel: View {
    @EnvironmentObject var store: Store
    @State private var troubleshooting = false
    @State private var notice: String?

    init(expandedDiagnostics: Bool = false) {
        _troubleshooting = State(initialValue: expandedDiagnostics)
    }
    private var heading: String {
        if !store.trusted { return "Allow window access" }
        if store.isRestoring { return "Putting your windows back…" }
        if store.learningProtected { return "Some windows couldn’t return" }
        if store.paused { return "Remembering paused" }
        return "Remembering your windows"
    }
    private var detail: String {
        if !store.trusted { return "Enable WindowRemember in Accessibility so it can remember and move your windows." }
        if store.isRestoring { return "Waiting for windows to settle into place." }
        if store.learningProtected { return store.restoreProblem ?? "Your saved positions are protected." }
        if store.paused { return "Your saved positions are kept." }
        return "They’ll return when your monitors reconnect."
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label { Text("WindowRemember") } icon: { Image(nsImage: TrayIcon.image) }.font(.headline).padding(.bottom, 22)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: !store.trusted ? "lock" : store.learningProtected ? "exclamationmark.circle" : store.isRestoring ? "arrow.triangle.2.circlepath" : store.paused ? "pause.circle" : "checkmark.circle")
                    .foregroundStyle(!store.trusted || store.learningProtected ? Color.orange : Color.accentColor).padding(.top, 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(heading).font(.system(size: 14, weight: .semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.bottom, 16)
            if !store.trusted {
                Button("Open Accessibility Settings") {
                    WindowAccess.request()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }.buttonStyle(.borderedProminent).controlSize(.large).padding(.bottom, 10)
                Text("Already enabled? Toggle it off and on after an app update.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Label(store.displays.map(\.name).joined(separator: " + "), systemImage: "display")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.bottom, 10)
                if store.learningProtected && !store.isRestoring {
                    Button("Try again") { store.restoreCurrent() }.buttonStyle(.borderedProminent).controlSize(.large)
                    Text("Your saved positions are protected.").font(.caption).foregroundStyle(.secondary).padding(.top, 7)
                }
            }
            Divider().padding(.vertical, 10)
            if store.trusted {
                menuButton(store.paused ? "Resume remembering" : "Pause remembering") { store.paused.toggle() }.disabled(store.isRestoring)
            }
            DisclosureGroup("Troubleshooting", isExpanded: $troubleshooting) {
                VStack(alignment: .leading, spacing: 9) {
                    Button("Open debug log") { NSWorkspace.shared.open(Diagnostics.directory) }
                    Button("Capture diagnostics") { store.captureDiagnostics(); notice = "Diagnostic snapshot saved locally." }
                    if store.learningProtected && store.trusted {
                        Button("Use current window positions instead") { store.adoptCurrentPositions() }.disabled(store.isRestoring)
                    }
                    if let error = store.storageProblem { Text(error).foregroundStyle(.orange) }
                    Text("Logs stay on this Mac and include window titles.").foregroundStyle(.secondary)
                    if store.loginNeedsAttention {
                        Button("Enable start at login…") { store.enableLogin() }
                    }
                }.font(.caption).buttonStyle(.link).padding(.top, 9).padding(.bottom, 5)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 5).padding(.vertical, 7)
            Divider().padding(.vertical, 8)
            menuButton("Quit WindowRemember", shortcut: "⌘Q") { NSApp.terminate(nil) }
            if let notice { Text(notice).font(.caption).foregroundStyle(.secondary).padding(.top, 9) }
        }.padding(18).frame(width: 330).tint(Color(red: 0.25, green: 0.62, blue: 0.49))
    }
    private func menuButton(_ title: String, shortcut: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); if let shortcut { Text(shortcut).foregroundStyle(.secondary) } }
                .contentShape(Rectangle()).padding(.horizontal, 5).padding(.vertical, 8)
        }.buttonStyle(.plain).font(.system(size: 13))
    }
}
