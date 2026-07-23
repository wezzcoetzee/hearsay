import Foundation

/// Turns a finished recording into a saved note. Owns the whole post-recording
/// sequence — transcribe, summarize, review participants, render, write — behind a
/// single call, so the ordering, cancellation, and participant-fork logic live in one
/// place and can be exercised through fakes at each seam.
@MainActor
struct NotePipeline {
    enum Stage: Equatable {
        case transcribing
        case identifyingSpeakers
        case summarizing
        case reviewing
        case saving
    }

    enum Outcome: Equatable {
        case saved(noteURL: URL?, folder: URL)
        case deleted
        case folderMissing
    }

    struct Input {
        let session: RecordingSession
        let model: String
        let diarize: Bool
        let summaryEnabled: Bool
        let detectedParticipants: [String]
        let outputFolder: URL?
    }

    let transcript: TranscriptBuilder
    let summarize: @MainActor ([TranscriptSegment]) async -> String?
    let confirmParticipants: (([String]) async -> [String]?)?
    var writeNote: (String, RecordingSource, Date, URL) throws -> URL = MarkdownWriter.write

    func run(_ input: Input, onStage: @MainActor (Stage) -> Void) async throws -> Outcome {
        let segments = try await transcript.build(
            system: input.session.systemAudioURL,
            mic: input.session.micAudioURL,
            model: input.model,
            diarize: input.diarize,
            hints: input.detectedParticipants
        ) { phase in
            switch phase {
            case .transcribing: onStage(.transcribing)
            case .identifyingSpeakers: onStage(.identifyingSpeakers)
            }
        }
        try Task.checkCancellation()

        if input.summaryEnabled { onStage(.summarizing) }
        let summary = await summarize(segments)
        try Task.checkCancellation()

        onStage(.reviewing)
        let candidates = ["Me"] + input.detectedParticipants.sorted()
        let participants: [String]
        if let confirmParticipants {
            guard let reviewed = await confirmParticipants(candidates) else {
                return .deleted
            }
            participants = reviewed
        } else {
            participants = candidates
        }

        let session = input.session
        session.participants = participants
        session.segmentCount = segments.count

        let metadata = NoteMetadata(
            date: session.startedAt,
            source: session.source,
            duration: session.duration,
            participants: participants
        )
        let markdown = MarkdownWriter.render(segments: segments, metadata: metadata, summary: summary)

        guard let folder = input.outputFolder else { return .folderMissing }
        onStage(.saving)
        session.noteURL = try writeNote(markdown, session.source, session.startedAt, folder)
        return .saved(noteURL: session.noteURL, folder: folder)
    }
}
