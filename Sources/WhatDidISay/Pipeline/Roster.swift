import Foundation

/// A distinct voice in a finished transcript, offered to the user for naming.
struct VoiceCandidate: Equatable, Sendable {
    /// The label the transcript currently uses, e.g. `Me`, `Others`, `Speaker 2`.
    let label: String
    /// Pre-filled name. Empty when we have no idea who this voice is.
    let suggestion: String
    /// A line this voice said, so the user has something to recognise them by.
    let sample: String

    var isPlaceholder: Bool { Speaker(label: label).isPlaceholder }
}

/// What review is asked to confirm: the voices heard, plus anyone we spotted on the
/// call roster who never got a voice of their own.
struct RosterReview: Equatable, Sendable {
    let voices: [VoiceCandidate]
    let others: [String]

    /// Distinct voices in the order they first speak, each carrying its opening line.
    static func voices(in segments: [TranscriptSegment], suggesting names: [String: String] = [:]) -> [VoiceCandidate] {
        var seen: Set<String> = []
        return segments.compactMap { segment in
            let label = segment.speaker.label
            guard seen.insert(label).inserted else { return nil }
            let speaker = segment.speaker
            return VoiceCandidate(
                label: label,
                suggestion: names[label] ?? (speaker.isPlaceholder ? "" : label),
                sample: segment.text
            )
        }
    }

    /// The roster we save when nobody reviews it: every voice keeps the name we guessed.
    var unreviewed: ReviewedRoster {
        ReviewedRoster(
            voices: voices.map { ReviewedVoice(label: $0.label, name: $0.suggestion) },
            others: others
        )
    }
}

struct ReviewedVoice: Equatable, Sendable {
    let label: String
    /// What the user called this voice. Empty leaves the transcript label alone.
    let name: String
}

/// The confirmed roster: who each voice was, and who else was in the room.
struct ReviewedRoster: Equatable, Sendable {
    let voices: [ReviewedVoice]
    let others: [String]

    /// Named voices first, in the order they spoke, then everyone else. Voices left as
    /// a placeholder aren't people we can name, so they don't make the roster.
    var participants: [String] {
        let named = voices.compactMap { voice -> String? in
            guard !voice.name.isEmpty, !Speaker(label: voice.name).isPlaceholder else { return nil }
            return voice.name
        }
        return named + others
    }

    func apply(to segments: [TranscriptSegment]) -> [TranscriptSegment] {
        let renames = Dictionary(
            voices.filter { !$0.name.isEmpty && $0.name != $0.label }.map { ($0.label, $0.name) },
            uniquingKeysWith: { _, latest in latest }
        )
        guard !renames.isEmpty else { return segments }
        return segments.map { segment in
            guard let name = renames[segment.speaker.label] else { return segment }
            return segment.relabeled(Speaker(label: name))
        }
    }
}
