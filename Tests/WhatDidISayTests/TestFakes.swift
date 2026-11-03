import Foundation
@testable import WhatDidISay

final class FakeTranscriber: Transcribing, @unchecked Sendable {
    var others: [TranscriptSegment] = []
    var mine: [TranscriptSegment] = []
    private(set) var receivedHints: [String] = []

    init(others: [TranscriptSegment] = [], mine: [TranscriptSegment] = []) {
        self.others = others
        self.mine = mine
    }

    /// Like the real transcriber, labels every segment with the speaker it was asked for,
    /// so a test sees whichever speaker the builder requested.
    func transcribe(url: URL, speaker: Speaker, model: String, hints: [String]) async throws -> [TranscriptSegment] {
        receivedHints = hints
        return (speaker == .others ? others : mine).map { $0.relabeled(speaker) }
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
