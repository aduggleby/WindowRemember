import XCTest
@testable import WindowRemember

final class DiagnosticRetentionTests: XCTestCase {
    func testRepeatedRotationsAndRestartsKeepEveryRecordAndLegacyLog() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = directory.appendingPathComponent("debug.previous.jsonl")
        try Data("legacy\n".utf8).write(to: legacy)
        // Recreate the writer each time to simulate repeated app launches/updates.
        for index in 0..<20 {
            try DiagnosticLogWriter(directory: directory, maximumFileSize: 1).append(Data("record-\(index)\n".utf8))
        }
        let archives = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("Archive"), includingPropertiesForKeys: nil)
        XCTAssertEqual(archives.count, 19)
        let files = archives + [directory.appendingPathComponent("debug.jsonl")]
        let records = try files.flatMap { try String(contentsOf: $0).split(separator: "\n").map(String.init) }
        XCTAssertEqual(Set(records), Set((0..<20).map { "record-\($0)" }))
        XCTAssertEqual(records.count, 20)
        XCTAssertEqual(try String(contentsOf: legacy), "legacy\n")
    }
    func testSmallWritesAppendWithoutPrematureRotation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = DiagnosticLogWriter(directory: directory, maximumFileSize: 100)
        try writer.append(Data("first\n".utf8))
        try writer.append(Data("second\n".utf8))
        XCTAssertEqual(try String(contentsOf: writer.file), "first\nsecond\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Archive").path))
    }
}
