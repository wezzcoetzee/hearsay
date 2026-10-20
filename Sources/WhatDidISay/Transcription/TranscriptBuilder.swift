import Foundation

/// Produces a single merged, speaker-labelled transcript from the recorded tracks.
/// Owns the recipe callers previously had to know: transcribe each track, diarize
/// the track carrying other people, then merge.
///
/// Calls have two tracks, so "Me" comes free from the microphone. An in-person
/// meeting has only the microphone — every voice in the room shares it — so there is
/// nothing to merge and diarization is the only thing separating speakers.
@MainActor
struct TranscriptBuilder {
    enum Phase: Sendable, Equatable {
        case transcribing
        case identifyingSpeakers
    }

    let transcriber: Transcribing
    let diarizer: Diarizing

    func build(
        system: URL?,
        mic: URL,
        model: String,
        diarize: Bool,
        hints: [String] = [],
        onProgress: (Phase) -> Void = { _ in }
    ) async throws -> [TranscriptSegment] {
        guard let system else {
            return try await buildFromMicAlone(mic: mic, model: model, diarize: diarize, hints: hints, onProgress: onProgress)
        }

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

    private func buildFromMicAlone(
        mic: URL,
        model: String,
        diarize: Bool,
        hints: [String],
        onProgress: (Phase) -> Void
    ) async throws -> [TranscriptSegment] {
        onProgress(.transcribing)
        // Nobody in the room is "Me" by virtue of the track they arrived on, so every
        // voice starts as an unnamed speaker and diarization splits them apart.
        var room = try await transcriber.transcribe(url: mic, speaker: .numbered(0), model: model, hints: hints)

        if diarize {
            onProgress(.identifyingSpeakers)
            if let spans = try? await diarizer.diarize(url: mic) {
                room = Diarizer.assignSpeakers(room, spans: spans)
            }
        }

        return room
    }
}
