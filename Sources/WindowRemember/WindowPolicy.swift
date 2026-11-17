import Foundation

enum WindowPolicy {
    static func layoutsMatch(_ lhs: [WindowRecord], _ rhs: [WindowRecord]) -> Bool {
        lhs.sorted { $0.id < $1.id } == rhs.sorted { $0.id < $1.id }
    }
    static func captures(role: String, subrole: String, minimized: Bool, fullscreen: Bool, positionSettable: Bool) -> Bool {
        guard role == "AXWindow", !minimized else { return false }
        if subrole == "AXStandardWindow" { return true }
        return (subrole == "AXUnknown" || subrole.isEmpty) && (positionSettable || fullscreen)
    }
    static func match(_ saved: WindowRecord, in candidates: [WindowRecord]) -> Int? {
        let sameApp = candidates.indices.filter { candidates[$0].bundleID == saved.bundleID }
        if !saved.title.isEmpty, let exact = sameApp.first(where: { candidates[$0].title == saved.title }) { return exact }
        // A connection browser must never stand in for an unavailable remote session.
        guard saved.bundleID != "com.microsoft.rdc.macos" else { return nil }
        return sameApp.first { candidates[$0].ordinal == saved.ordinal } ?? sameApp.first
    }
}
