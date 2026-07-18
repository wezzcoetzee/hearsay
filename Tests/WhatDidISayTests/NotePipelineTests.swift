import Foundation
import Testing
@testable import WhatDidISay

@Suite @MainActor struct NotePipelineTests {
    private let folder = URL(fileURLWithPath: "/tmp/vault")

    private func pipeline(
        others: [TranscriptSegment] = [makeSegment(0, "hi", .others)],
        summary: String? = nil,
        confirm: (([String]) async -> [String]?)? = { $0 },
        write: @escaping (String, RecordingSource, Date, URL) throws -> URL = { _, _, _, folder in folder.appendingPathComponent("note.md") }
    ) -> NotePipeline {
        NotePipeline(
            transcript: TranscriptBuilder(transcriber: FakeTranscriber(others: others), diarizer: FakeDiarizer()),
            summarize: { _ in summary },
            confirmParticipants: confirm,
            writeNote: write
        )
    }

    private func input(
        folder: URL? = URL(fileURLWithPath: "/tmp/vault"),
        summaryEnabled: Bool = false,
        participants: [String] = []
    ) -> NotePipeline.Input {
        NotePipeline.Input(
            session: RecordingSession(source: .slack),
            model: "base",
            diarize: false,
            summaryEnabled: summaryEnabled,
            detectedParticipants: participants,
            outputFolder: folder
        )
    }

    @Test func savedOutcomeWritesNoteAndPopulatesSession() async throws {
        let expected = folder.appendingPathComponent("note.md")
        var written: String?
        let pipe = pipeline(write: { markdown, _, _, _ in written = markdown; return expected })
        let inp = input(participants: ["Ada"])

        let outcome = try await pipe.run(inp) { _ in }

        #expect(outcome == .saved(noteURL: expected, folder: folder))
        #expect(inp.session.participants == ["Me", "Ada"])
        #expect(inp.session.segmentCount == 1)
        #expect(inp.session.noteURL == expected)
        #expect(written?.contains("hi") == true)
    }

    @Test func deletedWhenReviewReturnsNil() async throws {
        let outcome = try await pipeline(confirm: { _ in nil }).run(input()) { _ in }
        #expect(outcome == .deleted)
    }

    @Test func folderMissingWhenNoOutputFolder() async throws {
        let inp = input(folder: nil)
        let outcome = try await pipeline().run(inp) { _ in }
        #expect(outcome == .folderMissing)
        #expect(inp.session.segmentCount == 1)
    }

    @Test func usesConfirmedRosterOverCandidates() async throws {
        let inp = input(participants: ["Ada", "Grace"])
        _ = try await pipeline(confirm: { _ in ["Just Me"] }).run(inp) { _ in }
        #expect(inp.session.participants == ["Just Me"])
    }

    @Test func candidatesAreMeFirstThenSorted() async throws {
        var seen: [String] = []
        _ = try await pipeline(confirm: { candidates in seen = candidates; return candidates })
            .run(input(participants: ["Zoe", "Ada"])) { _ in }
        #expect(seen == ["Me", "Ada", "Zoe"])
    }

    @Test func skipsReviewWhenNoConfirmClosure() async throws {
        let inp = input(participants: ["Ada"])
        let outcome = try await pipeline(confirm: nil).run(inp) { _ in }
        #expect(inp.session.participants == ["Me", "Ada"])
        #expect(outcome == .saved(noteURL: folder.appendingPathComponent("note.md"), folder: folder))
    }

    @Test func emitsSummarizingStageOnlyWhenEnabled() async throws {
        var withSummary: [NotePipeline.Stage] = []
        _ = try await pipeline().run(input(summaryEnabled: true)) { withSummary.append($0) }
        #expect(withSummary.contains(.summarizing))

        var withoutSummary: [NotePipeline.Stage] = []
        _ = try await pipeline().run(input(summaryEnabled: false)) { withoutSummary.append($0) }
        #expect(!withoutSummary.contains(.summarizing))
    }

    @Test func emitsReviewingAndSavingForSavedFlow() async throws {
        var stages: [NotePipeline.Stage] = []
        _ = try await pipeline().run(input()) { stages.append($0) }
        #expect(stages.contains(.reviewing))
        #expect(stages.contains(.saving))
    }

    @Test func doesNotEmitSavingWhenFolderMissing() async throws {
        var stages: [NotePipeline.Stage] = []
        _ = try await pipeline().run(input(folder: nil)) { stages.append($0) }
        #expect(!stages.contains(.saving))
    }
}
