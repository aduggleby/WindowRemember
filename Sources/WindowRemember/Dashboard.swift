import SwiftUI
import AppKit

private let accent = Color(red: 0.34, green: 0.79, blue: 0.65)
struct Dashboard: View {
    @EnvironmentObject var store: Store
    @State private var tab = "Overview"
    @State private var sceneName = ""
    @State private var showingScene = false
    let items = [("Overview", "square.grid.2x2"), ("Scenes", "rectangle.3.group"), ("Display setups", "display.2"), ("History", "clock.arrow.circlepath"), ("Settings", "slider.horizontal.3")]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.3.group.fill").font(.title2).foregroundStyle(accent)
                    VStack(alignment: .leading) { Text("Window").font(.headline); Text("Remember").font(.headline) }
                }.padding(.bottom, 32).padding(.top, 20)
                Text("WORKSPACE").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary).padding(.bottom, 6)
                ForEach(items, id: \.0) { item in
                    Button { tab = item.0 } label: {
                        HStack(spacing: 12) { Image(systemName: item.1).frame(width: 18); Text(item.0); Spacer() }
                            .font(.system(size: 13, weight: tab == item.0 ? .semibold : .regular))
                            .padding(12).background(tab == item.0 ? accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(tab == item.0 ? accent : .secondary)
                    }.buttonStyle(.plain)
                }
                Spacer()
                HStack(spacing: 7) { Circle().fill(store.paused ? .orange : accent).frame(width: 6, height: 6); Text(store.paused ? "Learning paused" : "Quietly remembering").font(.caption) }.foregroundStyle(.secondary)
                Text("On this Mac. Always private.").font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 4)
            }.padding(20).frame(width: 210).background(Color.white.opacity(0.025))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("YOUR DESK, REMEMBERED").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(accent)
                        Spacer()
                        Label("LOCAL ONLY", systemImage: "lock.shield").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title).font(.system(size: 32, weight: .semibold))
                            Text(subtitle).foregroundStyle(.secondary).font(.system(size: 13))
                        }
                        Spacer()
                        if tab == "Scenes" { Button("New scene", systemImage: "plus") { showingScene = true }.buttonStyle(MintButtonStyle()) }
                    }
                    if !store.trusted { permissionCard }
                    switch tab {
                    case "Scenes": scenes
                    case "Display setups": setups
                    case "History": history
                    case "Settings": settings
                    default: overview
                    }
                    HStack { Image(systemName: "checkmark.circle").foregroundStyle(accent); Text(store.status).font(.caption).foregroundStyle(.secondary) }.padding(.top, 4)
                }.padding(36)
            }
        }.background(Color(red: 0.055, green: 0.075, blue: 0.08)).preferredColorScheme(.dark).tint(accent)
        .sheet(isPresented: $showingScene) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Save this moment.").font(.title2.bold())
                Text("Capture your open windows as a scene you can return to.").foregroundStyle(.secondary)
                TextField("Scene name, e.g. Deep work", text: $sceneName).textFieldStyle(.roundedBorder).onSubmit { saveScene() }
                HStack { Button("Cancel") { showingScene = false }; Spacer(); Button("Save scene") { saveScene() }.buttonStyle(.borderedProminent).disabled(sceneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.trusted) }
            }.padding(28).frame(width: 420)
        }
    }
    var title: String { switch tab { case "Overview": "Everything in its place."; case "Scenes": "A desk for every mode."; case "Display setups": "Every setup has a memory."; case "History": "A little peace of mind."; default: "Make yourself at home." } }
    var subtitle: String { switch tab { case "Overview": "Leave your desk. Come back to exactly where you were."; case "Scenes": "Save an arrangement. Bring it back whenever you need it."; case "Display setups": "Your windows are remembered separately for each set of displays."; case "History": "See what was restored, and when."; default: "Simple controls for a calmer workspace." } }
    func saveScene() { store.saveScene(sceneName); sceneName = ""; showingScene = false }
    var permissionCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "hand.raised.fill").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 5) { Text("One permission. Then you're set.").font(.headline); Text("Allow Accessibility to read and move your windows. Layouts stay on your Mac.").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button("Enable access") { WindowAccess.request(); NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }.buttonStyle(.bordered)
        }.padding(20).background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
    var overview: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Label("CURRENT SETUP", systemImage: "display").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary); Spacer(); Text("\(store.displays.count) connected").font(.caption).foregroundStyle(accent) }
                DisplayCanvas(windows: store.currentWindows, displays: store.displays).frame(height: 210)
                HStack {
                    VStack(alignment: .leading, spacing: 5) { Text(store.displays.map(\.name).joined(separator: " + ")).font(.headline); Text("\(store.currentWindows.count) windows · Updated automatically").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Put windows back", systemImage: "arrow.uturn.backward") { store.restoreCurrent() }.buttonStyle(MintButtonStyle()).disabled(!store.trusted)
                }
            }.card()
            HStack(spacing: 16) {
                metric("display.2", "\(store.archive.layouts.count)", "Remembered setups")
                metric("rectangle.3.group", "\(store.archive.scenes.count)", "Saved scenes")
                metric("arrow.uturn.backward", "\(store.archive.history.count)", "Restores recorded")
            }
            HStack {
                VStack(alignment: .leading, spacing: 6) { Text("Your next focus session, one click away.").font(.headline); Text("Save your current arrangement as a named scene.").font(.caption).foregroundStyle(.secondary) }
                Spacer(); Button("Save a scene", systemImage: "plus") { showingScene = true }.buttonStyle(.bordered).disabled(!store.trusted)
            }.card()
        }
    }
    func metric(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 12) { Image(systemName: icon).foregroundStyle(accent); Text(value).font(.system(size: 28, weight: .medium)); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).card()
    }
    var scenes: some View {
        VStack(spacing: 14) {
            if store.archive.scenes.isEmpty { empty("rectangle.3.group", "Room for a new routine.", "Arrange your windows, then save your first scene.") }
            ForEach(store.archive.scenes) { scene in
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Image(systemName: "rectangle.3.group.fill").foregroundStyle(accent); Text(scene.name).font(.headline); Spacer(); Text("\(scene.windows.count) windows").font(.caption).foregroundStyle(.secondary) }
                    HStack { Text(scene.updated, style: .date).font(.caption).foregroundStyle(.secondary); Spacer(); Button(role: .destructive) { store.deleteScene(scene.id) } label: { Image(systemName: "trash") }; Button("Apply scene") { store.restore(scene, reason: "Scene") }.buttonStyle(.borderedProminent).disabled(!store.trusted) }
                }.card()
            }
        }
    }
    var setups: some View {
        VStack(spacing: 14) {
            if store.archive.layouts.isEmpty { empty("display.2", "Getting to know your desk.", "Enable Accessibility and arrange your windows to start learning.") }
            ForEach(store.archive.layouts.keys.sorted(), id: \.self) { key in
                if let layout = store.archive.layouts[key] {
                    HStack {
                        Image(systemName: "display.2").font(.title).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 6) { Text(layout.name).font(.headline); Text("\(layout.windows.count) windows · \(layout.pinned ? "Pinned" : "Learning")").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button { store.togglePin(key) } label: { Image(systemName: layout.pinned ? "pin.fill" : "pin") }.help("Pin to stop automatic learning")
                        Button("Restore") { store.restore(layout, reason: "Saved setup") }.disabled(key != DisplayInfo.signature || !store.trusted)
                    }.card()
                }
            }
        }
    }
    var history: some View {
        VStack(spacing: 12) {
            HStack { Button("Undo last restore") { store.undo() }.disabled(!store.canUndo); Spacer(); Button("Clear history") { store.archive.history = []; store.persist() }.disabled(store.archive.history.isEmpty) }
            if store.archive.history.isEmpty { empty("clock.arrow.circlepath", "A fresh start.", "Your restore activity will appear here.") }
            ForEach(store.archive.history) { event in
                HStack(spacing: 14) {
                    Image(systemName: event.skipped == 0 ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(event.skipped == 0 ? accent : .orange)
                    VStack(alignment: .leading, spacing: 5) { Text(event.reason).font(.system(size: 12, weight: .medium)); Text("\(event.moved) restored · \(event.skipped) unavailable").font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Text(event.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                }.card()
            }
        }
    }
    var settings: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 20) {
                Toggle("Restore when displays change or the Mac wakes", isOn: $store.automatic)
                Toggle("Pause automatic learning", isOn: $store.paused)
                Divider()
                Text("Restore shortcut: ⇧⌘R while WindowRemember is active.").font(.caption).foregroundStyle(.secondary)
                Text("Pinned setups keep their saved arrangement. Unpin a setup to resume learning.").font(.caption).foregroundStyle(.secondary)
            }.card()
            VStack(alignment: .leading, spacing: 14) {
                Text("Ignore applications").font(.headline)
                Text("Ignored apps are excluded from future captures and restores.").font(.caption).foregroundStyle(.secondary)
                ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }, id: \.processIdentifier) { app in
                    if let bundle = app.bundleIdentifier {
                        Toggle(app.localizedName ?? bundle, isOn: Binding(get: { store.archive.ignoredApps.contains(bundle) }, set: { store.setIgnored(bundle, ignored: $0) }))
                    }
                }
            }.card()
            Text("WindowRemember works with accessible standard windows on the current desktop. Closed apps, minimized windows, full-screen windows and other Spaces are not restored. Scenes require their apps to be open.").font(.caption).foregroundStyle(.secondary)
        }
    }
    func empty(_ icon: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 14) { Image(systemName: icon).font(.system(size: 36)).foregroundStyle(accent); Text(title).font(.title3.bold()); Text(detail).foregroundStyle(.secondary).font(.caption) }.frame(maxWidth: .infinity).padding(.vertical, 70).card()
    }
}
private extension View {
    func card() -> some View { self.padding(22).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.07), lineWidth: 1)) }
}
struct DisplayCanvas: View {
    var windows: [WindowRecord]
    var displays: [DisplayInfo]
    var body: some View {
        GeometryReader { geometry in
            let union = displays.reduce(CGRect.null) { $0.union($1.frame) }
            let scale = min((geometry.size.width - 30) / max(union.width, 1), (geometry.size.height - 25) / max(union.height, 1))
            let offsetX = (geometry.size.width - union.width * scale) / 2
            let offsetY = (geometry.size.height - union.height * scale) / 2
            ZStack(alignment: .topLeading) {
                ForEach(displays) { display in
                    let x = offsetX + (display.frame.minX - union.minX) * scale
                    let y = offsetY + (display.frame.minY - union.minY) * scale
                    RoundedRectangle(cornerRadius: 7).fill(accent.opacity(0.04)).overlay(RoundedRectangle(cornerRadius: 7).stroke(accent.opacity(0.35), lineWidth: 1.5)).frame(width: display.frame.width * scale, height: display.frame.height * scale).offset(x: x, y: y)
                    ForEach(Array(windows.filter { $0.displayID == display.id }.enumerated()), id: \.offset) { index, window in
                        RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.08 + Double(index % 3) * 0.04)).overlay(alignment: .topLeading) { Text(window.appName).font(.system(size: 8)).foregroundStyle(accent.opacity(0.9)).padding(5) }.overlay(RoundedRectangle(cornerRadius: 3).stroke(accent.opacity(0.4))).frame(width: max(1, min(window.width, display.frame.width) * scale), height: max(1, min(window.height, display.frame.height) * scale)).clipped().offset(x: x + max(0, window.x) * scale, y: y + max(0, window.y) * scale)
                    }
                    if windows.isEmpty { Text(display.name).font(.caption).foregroundStyle(.secondary).offset(x: x + 14, y: y + 14) }
                }
            }
        }
    }
}

struct MintButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .foregroundStyle(enabled ? Color.black : Color.white.opacity(0.4))
            .padding(.horizontal, 15).padding(.vertical, 10)
            .background(enabled ? accent.opacity(configuration.isPressed ? 0.7 : 1) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }
}
