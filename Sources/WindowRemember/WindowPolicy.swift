import Foundation

enum WindowPolicy {
    // Restoration can proceed independently for available windows. Learning stays stricter
    // so a partial capture cannot replace the saved layout.
    static func restoreCaptureIsReady(captured: [WindowRecord], invalidRoles: Bool, unreliableBundles: Set<String> = []) -> Bool {
        !invalidRoles && (!captured.isEmpty || unreliableBundles.isEmpty)
    }
    static func captureIsReady(expected: [WindowRecord], captured: [WindowRecord], runningBundles: Set<String>, unreliableBundles: Set<String>, invalidRoles: Bool) -> Bool {
        guard !invalidRoles else { return false }
        let expectedRunning = Set(expected.map(\.bundleID)).intersection(runningBundles)
        guard expectedRunning.isDisjoint(with: unreliableBundles) else { return false }
        return true
    }
    static func unmatchedIsFailure(_ saved: WindowRecord, unreliableBundles: Set<String>) -> Bool {
        unreliableBundles.contains(saved.bundleID)
    }
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
