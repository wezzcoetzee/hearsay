import Foundation
@testable import WhatDidISay

struct FakeTranscriber: Transcribing {
    var others: [TranscriptSegment] = []
    var mine: [TranscriptSegment] = []

    func transcribe(url: URL, speaker: Speaker, model: String) async throws -> [TranscriptSegment] {
        speaker == .others ? others : mine
    }
}

struct FakeDiarizer: Diarizing {
    var spans: [SpeakerSpan] = []
    var shouldThrow = false

    func diarize(url: URL) async throws -> [SpeakerSpan] {
        if shouldThrow { throw FakeError.diarizationFailed }
        return spans
    }
}

enum FakeError: Error {
    case diarizationFailed
}

func makeSegment(_ start: Double, _ text: String, _ speaker: Speaker) -> TranscriptSegment {
    TranscriptSegment(start: start, end: start + 1, text: text, speaker: speaker)
}
