import Foundation

/// Produces a single merged, speaker-labelled transcript from the two recorded
/// tracks. Owns the recipe callers previously had to know: transcribe each track,
/// diarize the others track when asked, then merge.
@MainActor
struct TranscriptBuilder {
    enum Phase: Sendable, Equatable {
        case transcribing
        case identifyingSpeakers
    }

    let transcriber: Transcribing
    let diarizer: Diarizing

    func build(
        system: URL,
        mic: URL,
        model: String,
        diarize: Bool,
        hints: [String] = [],
        onProgress: (Phase) -> Void = { _ in }
    ) async throws -> [TranscriptSegment] {
        onProgress(.transcribing)
        var others = try await transcriber.transcribe(url: system, speaker: .others, model: model, hints: hints)
        let mine = try await transcriber.transcribe(url: mic, speaker: .me, model: model, hints: hints)

        if diarize {
            onProgress(.identifyingSpeakers)
            if let spans = try? await diarizer.diarize(url: system) {
                others = Diarizer.assignSpeakers(others, spans: spans)
            }
        }

        return TranscriptMerger.merge(others, mine)
    }
}
