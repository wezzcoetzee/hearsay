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

    /// Labels each segment with the speaker whose span covers its midpoint. Whisper and
    /// the diarizer rarely agree on exact boundaries, so a midpoint that falls in a gap
    /// goes to the nearest span rather than keeping a generic label.
    static func assignSpeakers(_ segments: [TranscriptSegment], spans: [SpeakerSpan]) -> [TranscriptSegment] {
        let known = spans.filter { $0.speakerId >= 0 }
        guard !known.isEmpty else { return segments }
        return segments.map { segment in
            let midpoint = (segment.start + segment.end) / 2
            let nearest = known.min { distance(from: midpoint, to: $0) < distance(from: midpoint, to: $1) }
            return nearest.map { segment.relabeled(.numbered($0.speakerId)) } ?? segment
        }
    }

    private static func distance(from time: Double, to span: SpeakerSpan) -> Double {
        if time < span.start { return span.start - time }
        if time > span.end { return time - span.end }
        return 0
    }
}
