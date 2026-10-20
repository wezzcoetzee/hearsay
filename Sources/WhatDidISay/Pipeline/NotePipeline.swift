import Foundation

/// Turns a finished recording into a saved note. Owns the whole post-recording
/// sequence — transcribe, review participants, summarize, render, write — behind a
/// single call, so the ordering, cancellation, and participant-fork logic live in one
/// place and can be exercised through fakes at each seam.
///
/// Review comes before the summary on purpose: a call the user deletes never reaches
/// a summarizer (which may be in the cloud), and the summary sees real names.
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
    let confirmRoster: ((RosterReview) async -> ReviewedRoster?)?
    var writeNote: (String, RecordingSource, Date, URL) throws -> URL = MarkdownWriter.write

    func run(_ input: Input, onStage: @MainActor (Stage) -> Void) async throws -> Outcome {
        // Checked up front so the user can fix it and retry before minutes of transcription.
        guard let folder = input.outputFolder else { return .folderMissing }

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

        onStage(.reviewing)
        let review = RosterReview(
            voices: RosterReview.voices(in: segments),
            others: input.detectedParticipants.sorted()
        )
        let roster: ReviewedRoster
        if let confirmRoster {
            let reviewed = await confirmRoster(review)
            // Cancelling closes the review too; that `nil` isn't a request to delete.
            try Task.checkCancellation()
            guard let reviewed else { return .deleted }
            roster = reviewed
        } else {
            roster = review.unreviewed
        }
        let named = roster.apply(to: segments)

        if input.summaryEnabled { onStage(.summarizing) }
        let summary = await summarize(named)
        try Task.checkCancellation()

        let session = input.session
        session.participants = roster.participants
        session.segmentCount = named.count

        let metadata = NoteMetadata(
            date: session.startedAt,
            source: session.source,
            duration: session.duration,
            participants: roster.participants
        )
        let markdown = MarkdownWriter.render(segments: named, metadata: metadata, summary: summary)

        onStage(.saving)
        session.noteURL = try writeNote(markdown, session.source, session.startedAt, folder)
        return .saved(noteURL: session.noteURL, folder: folder)
    }
}
