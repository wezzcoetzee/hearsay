import Foundation
import SpeakerKit
import WhisperKit

struct SpeakerSpan: Sendable {
    let start: Double
    let end: Double
    let speakerId: Int
}

protocol Diarizing: Sendable {
    func diarize(url: URL) async throws -> [SpeakerSpan]
}

final class Diarizer: Diarizing, @unchecked Sendable {
    private var kit: SpeakerKit?

    func diarize(url: URL) async throws -> [SpeakerSpan] {
        if kit == nil { kit = try await SpeakerKit() }
        guard let kit else { return [] }

        let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        let result = try await kit.diarize(audioArray: audio)
        return result.segments.map {
            SpeakerSpan(start: Double($0.startTime), end: Double($0.endTime), speakerId: $0.speaker.speakerId ?? -1)
        }
    }

    static func assignSpeakers(_ segments: [TranscriptSegment], spans: [SpeakerSpan]) -> [TranscriptSegment] {
        guard !spans.isEmpty else { return segments }
        return segments.map { segment in
            let midpoint = (segment.start + segment.end) / 2
            if let span = spans.first(where: { midpoint >= $0.start && midpoint <= $0.end }), span.speakerId >= 0 {
                return segment.relabeled(.numbered(span.speakerId))
            }
            return segment
        }
    }
}
