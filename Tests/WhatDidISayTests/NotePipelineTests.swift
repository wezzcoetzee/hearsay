import Foundation
import Testing
@testable import WhatDidISay

@Suite @MainActor struct NotePipelineTests {
    private let folder = URL(fileURLWithPath: "/tmp/vault")

    private func pipeline(
        others: [TranscriptSegment] = [makeSegment(0, "hi", .others)],
        mine: [TranscriptSegment] = [],
        summary: String? = nil,
        confirm: ((RosterReview) async -> ReviewedRoster?)? = { $0.unreviewed },
        write: @escaping (String, RecordingSource, Date, URL) throws -> URL = { _, _, _, folder in folder.appendingPathComponent("note.md") }
    ) -> NotePipeline {
        NotePipeline(
            transcript: TranscriptBuilder(transcriber: FakeTranscriber(others: others, mine: mine), diarizer: FakeDiarizer()),
            summarize: { _ in summary },
            confirmRoster: confirm,
            writeNote: write
        )
    }

    private func input(
        folder: URL? = URL(fileURLWithPath: "/tmp/vault"),
        summaryEnabled: Bool = false,
        participants: [String] = [],
        source: RecordingSource = .slack
    ) -> NotePipeline.Input {
        NotePipeline.Input(
            session: RecordingSession(source: source, in: FileManager.default.temporaryDirectory),
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
        let pipe = pipeline(others: [makeSegment(0, "hi", .me)],
                            write: { markdown, _, _, _ in written = markdown; return expected })
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

    @Test func folderMissingBailsBeforeAnyWork() async throws {
        var stages: [NotePipeline.Stage] = []
        let outcome = try await pipeline().run(input(folder: nil)) { stages.append($0) }
        #expect(outcome == .folderMissing)
        #expect(stages.isEmpty)
    }

    @Test func reviewsBeforeSummarizing() async throws {
        var stages: [NotePipeline.Stage] = []
        _ = try await pipeline().run(input(summaryEnabled: true)) { stages.append($0) }
        let review = try #require(stages.firstIndex(of: .reviewing))
        let summary = try #require(stages.firstIndex(of: .summarizing))
        #expect(review < summary)
    }

    @Test func deletedCallIsNeverSummarized() async throws {
        var summarized = false
        let pipe = NotePipeline(
            transcript: TranscriptBuilder(transcriber: FakeTranscriber(others: [makeSegment(0, "hi", .others)]),
                                          diarizer: FakeDiarizer()),
            summarize: { _ in summarized = true; return "summary" },
            confirmRoster: { _ in nil }
        )
        let outcome = try await pipe.run(input(summaryEnabled: true)) { _ in }
        #expect(outcome == .deleted)
        #expect(!summarized)
    }

    @Test func summarySeesTheNamesFromReview() async throws {
        var summarizedSpeakers: [String] = []
        let roster = ReviewedRoster(voices: [ReviewedVoice(label: "Others", name: "Ada")], others: [])
        let pipe = NotePipeline(
            transcript: TranscriptBuilder(transcriber: FakeTranscriber(others: [makeSegment(0, "hi", .others)]),
                                          diarizer: FakeDiarizer()),
            summarize: { segments in summarizedSpeakers = segments.map(\.speaker.label); return nil },
            confirmRoster: { _ in roster },
            writeNote: { _, _, _, folder in folder }
        )
        _ = try await pipe.run(input(summaryEnabled: true)) { _ in }
        #expect(summarizedSpeakers == ["Ada"])
    }

    @Test func usesConfirmedRosterOverCandidates() async throws {
        let inp = input(participants: ["Ada", "Grace"])
        let roster = ReviewedRoster(voices: [], others: ["Just Me"])
        _ = try await pipeline(confirm: { _ in roster }).run(inp) { _ in }
        #expect(inp.session.participants == ["Just Me"])
    }

    @Test func reviewSeesEveryVoiceAndTheDetectedRosterSorted() async throws {
        var seen: RosterReview?
        let segments = [makeSegment(0, "hello", .others), makeSegment(1, "hi back", .me)]
        _ = try await pipeline(others: segments, confirm: { request in seen = request; return request.unreviewed })
            .run(input(participants: ["Zoe", "Ada"])) { _ in }

        #expect(seen?.voices.map(\.label) == ["Others", "Me"])
        #expect(seen?.voices.map(\.sample) == ["hello", "hi back"])
        #expect(seen?.others == ["Ada", "Zoe"])
    }

    @Test func namingAVoiceRelabelsTheTranscriptAndTheRoster() async throws {
        var written: String?
        let segments = [makeSegment(0, "morning all", .numbered(1))]
        let roster = ReviewedRoster(voices: [ReviewedVoice(label: "Speaker 2", name: "Ada")], others: [])
        let inp = input(source: .inPerson)

        _ = try await pipeline(mine: segments,
                               confirm: { _ in roster },
                               write: { markdown, _, _, folder in written = markdown; return folder })
            .run(inp) { _ in }

        #expect(written?.contains("Ada:** morning all") == true)
        #expect(inp.session.participants == ["Ada"])
    }

    @Test func unnamedVoicesStayOutOfTheRoster() async throws {
        let segments = [makeSegment(0, "hi", .numbered(0)), makeSegment(1, "hello", .me)]
        let inp = input(source: .inPerson)
        _ = try await pipeline(mine: segments).run(inp) { _ in }
        #expect(inp.session.participants == ["Me"])
    }

    @Test func skipsReviewWhenNoConfirmClosure() async throws {
        let inp = input(participants: ["Ada"])
        let outcome = try await pipeline(others: [makeSegment(0, "hi", .me)], confirm: nil).run(inp) { _ in }
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

    @Test func retryReusesTheSavedTranscriptInsteadOfTranscribingAgain() async throws {
        let inp = input()
        defer { inp.session.deleteRecording() }
        try inp.session.saveTranscript([makeSegment(0, "from the first run", .me)])

        var written: String?
        _ = try await pipeline(others: [makeSegment(0, "transcribed again", .others)],
                               write: { markdown, _, _, folder in written = markdown; return folder })
            .run(inp) { _ in }

        #expect(written?.contains("from the first run") == true)
        #expect(written?.contains("transcribed again") == false)
    }
}
