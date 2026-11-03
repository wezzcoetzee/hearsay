import Foundation
import Testing
@testable import WhatDidISay

@Suite @MainActor final class RecordingHistoryTests {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("RecordingHistoryTests-\(UUID().uuidString)", isDirectory: true)
    private var fileURL: URL { folder.appendingPathComponent("history.json") }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private func session() -> RecordingSession {
        RecordingSession(source: .slack, in: folder.appendingPathComponent("Recordings"))
    }

    @Test func entriesSurviveARelaunch() {
        let recorded = session()
        RecordingHistory(fileURL: fileURL).add(recorded)

        #expect(RecordingHistory(fileURL: fileURL).entries.map(\.id) == [recorded.id])
    }

    @Test func anUnreadableFileIsMovedAsideInsteadOfBeingOverwritten() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        let history = RecordingHistory(fileURL: fileURL)
        history.add(session())

        #expect(history.entries.count == 1)
        let backups = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("history.corrupt-") }
        #expect(backups.count == 1)
        #expect(try String(contentsOf: try #require(backups.first), encoding: .utf8) == "not json")
        #expect(RecordingHistory(fileURL: fileURL).entries.count == 1)
    }
}
