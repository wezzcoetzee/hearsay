import Foundation

/// Produces a single merged, speaker-labelled transcript from the recorded tracks.
/// Owns the recipe callers previously had to know: transcribe each track, diarize
/// the track carrying other people, then merge.
///
/// Calls have two tracks, so "Me" comes free from the microphone. An in-person
/// meeting has only the microphone — every voice in the room shares it — so there is
/// nothing to merge and diarization is the only thing separating speakers.
///
/// A failed diarization doesn't fail the build: the transcript still reads, just without
/// the speaker split. `diarizationFailed` tells callers it is a degraded result.
@MainActor
struct TranscriptBuilder {
    enum Phase: Sendable, Equatable {
        case transcribing
        case identifyingSpeakers
    }

    typealias Built = (segments: [TranscriptSegment], diarizationFailed: Bool)

    let transcriber: Transcribing
    let diarizer: Diarizing

    func build(
        system: URL?,
        mic: URL,
        model: String,
        diarize: Bool,
        hints: [String] = [],
        onProgress: (Phase) -> Void = { _ in }
    ) async throws -> Built {
        guard let system else {
            return try await buildFromMicAlone(mic: mic, model: model, diarize: diarize, hints: hints, onProgress: onProgress)
        }

        onProgress(.transcribing)
        var others = try await transcriber.transcribe(url: system, speaker: .others, model: model, hints: hints)
        let mine = try await transcriber.transcribe(url: mic, speaker: .me, model: model, hints: hints)

        var diarizationFailed = false
        if diarize {
            (others, diarizationFailed) = try await diarized(others, audio: system, onProgress: onProgress)
        }

        return (TranscriptMerger.merge(others, mine), diarizationFailed)
    }

    private func buildFromMicAlone(
        mic: URL,
        model: String,
        diarize: Bool,
        hints: [String],
        onProgress: (Phase) -> Void
    ) async throws -> Built {
        onProgress(.transcribing)
        // Nobody in the room is "Me" by virtue of the track they arrived on, so every
        // voice starts as an unnamed speaker and diarization splits them apart.
        let room = try await transcriber.transcribe(url: mic, speaker: .numbered(0), model: model, hints: hints)

        guard diarize else { return (room, false) }
        return try await diarized(room, audio: mic, onProgress: onProgress)
    }

    private func diarized(
        _ segments: [TranscriptSegment],
        audio: URL,
        onProgress: (Phase) -> Void
    ) async throws -> Built {
        onProgress(.identifyingSpeakers)
        do {
            return (Diarizer.assignSpeakers(segments, spans: try await diarizer.diarize(url: audio)), false)
        } catch {
            try Task.checkCancellation()
            NSLog("Diarization failed, keeping unsplit speakers: \(error)")
            return (segments, true)
        }
    }
}
