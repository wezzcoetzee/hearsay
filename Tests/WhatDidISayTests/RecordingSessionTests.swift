import Foundation
import Testing

@testable import WhatDidISay

@Suite struct RecordingSessionTests {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("RecordingSessionTests-\(UUID().uuidString)", isDirectory: true)

    private func recording(_ source: RecordingSource = .slack, progress: RecordingSession.Progress) throws
        -> RecordingSession
    {
        let session = RecordingSession(source: source, in: folder)
        session.detectedParticipants = ["Ada"]
        try session.advance(to: progress)
        FileManager.default.createFile(atPath: session.micAudioURL.path, contents: Data())
        return session
    }

    @Test func findsUnfinishedRecordingsAndRestoresWhatTheyKnew() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let crashed = try recording(.teams, progress: .recording)
        _ = try recording(progress: .noted)

        let found = RecordingSession.unfinished(in: folder)

        #expect(found.map(\.id) == [crashed.id])
        #expect(found.first?.source == .teams)
        #expect(found.first?.detectedParticipants == ["Ada"])
        // Never stopped, so the end comes from the mic track's last write.
        #expect(found.first?.finishedAt != nil)
    }

    @Test func recoversFoldersFromBeforeProgressWasTracked() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let legacy = folder.appendingPathComponent("2026-10-28_08-34-56_56CF2342", isDirectory: true)
        let saved = folder.appendingPathComponent("2026-10-21_09-02-25_7BCFFF99", isDirectory: true)
        let empty = folder.appendingPathComponent("2026-07-15_10-47-37_9B5A75EA", isDirectory: true)
        for dir in [legacy, saved, empty] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        for dir in [legacy, saved] {
            FileManager.default.createFile(atPath: dir.appendingPathComponent("mic.caf").path, contents: Data())
        }

        let found = RecordingSession.unfinished(in: folder, notedPaths: [saved.path])

        #expect(found.map(\.directory.lastPathComponent) == [legacy.lastPathComponent])
        #expect(found.first?.progress == .recorded)
        let start = DateComponents(calendar: .current, year: 2026, month: 10, day: 28, hour: 8, minute: 34, second: 56)
            .date
        #expect(found.first?.startedAt == start)
    }

    @Test func savedTranscriptSurvivesARelaunch() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = try recording(progress: .recorded)
        try session.saveTranscript([makeSegment(0, "hello", .me)])

        let recovered = try #require(RecordingSession.unfinished(in: folder).first)

        #expect(recovered.progress == .transcribed)
        #expect(recovered.savedTranscript?.map(\.text) == ["hello"])
    }
}
