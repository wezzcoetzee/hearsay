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

/// What review is asked to confirm: the voices heard, plus names read off the call
/// window. Those are only guesses (a Slack window shows channel names too), so none of
/// them reach the note unless the user ticks them.
struct RosterReview: Equatable, Sendable {
    let voices: [VoiceCandidate]
    let others: [String]

    /// Distinct voices in the order they first speak, each carrying its opening line.
    static func voices(in segments: [TranscriptSegment]) -> [VoiceCandidate] {
        var seen: Set<String> = []
        return segments.compactMap { segment in
            let label = segment.speaker.label
            guard seen.insert(label).inserted else { return nil }
            let speaker = segment.speaker
            return VoiceCandidate(
                label: label,
                suggestion: speaker.isPlaceholder ? "" : label,
                sample: segment.text
            )
        }
    }

    /// The roster we save when nobody reviews it: every voice keeps the name we guessed,
    /// and no names read off the screen, matching the dialog's unticked default.
    var unreviewed: ReviewedRoster {
        ReviewedRoster(
            voices: voices.map { ReviewedVoice(label: $0.label, name: $0.suggestion) },
            others: []
        )
    }

    /// Where a voice's lines go when the user says it isn't a separate person: the
    /// nearest voice above that is still its own person, else the nearest below.
    /// `Me` is the mic track, so a call voice never folds into it, nor it into one.
    static func mergeTarget(for index: Int, in voices: [VoiceCandidate], merged: Set<Int>) -> Int? {
        let isMe = { voices[$0].label == Speaker.me.label }
        guard voices.indices.contains(index), !isMe(index) else { return nil }
        let open = { (i: Int) in i != index && !merged.contains(i) && !isMe(i) }
        return voices.indices[..<index].reversed().first(where: open)
            ?? voices.indices[(index + 1)...].first(where: open)
    }

    /// The reviewed voices for the names typed in, with each merged voice taking the
    /// name of the voice it was folded into. A merge target may itself be merged later,
    /// so the chain is followed to the voice that kept its own row.
    static func reviewed(_ voices: [VoiceCandidate], names: [String], mergedInto: [Int: Int]) -> [ReviewedVoice] {
        func owner(_ index: Int) -> Int {
            mergedInto[index].map(owner) ?? index
        }
        return voices.indices.map { index in
            let root = owner(index)
            let typed = names[root].trimmingCharacters(in: .whitespaces)
            let name = root == index ? typed : (typed.isEmpty ? voices[root].label : typed)
            return ReviewedVoice(label: voices[index].label, name: name)
        }
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

    /// Named voices first, in the order they spoke, then everyone else, each once: two
    /// voices given one name are one person. Voices left as a placeholder aren't people
    /// we can name, so they don't make the roster.
    var participants: [String] {
        let named = voices.compactMap { voice -> String? in
            guard !voice.name.isEmpty, !Speaker(label: voice.name).isPlaceholder else { return nil }
            return voice.name
        }
        var seen: Set<String> = []
        return (named + others).filter { seen.insert($0).inserted }
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
