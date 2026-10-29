import Foundation

struct Speaker: Equatable, Codable, Sendable {
    private static let numberedPrefix = "Speaker "

    let label: String

    static let me = Speaker(label: "Me")
    static let others = Speaker(label: "Others")
    static func numbered(_ id: Int) -> Speaker { Speaker(label: "\(numberedPrefix)\(id + 1)") }

    /// A placeholder stands in for a voice we couldn't put a name to. Those voices are
    /// offered for naming during review, and stay out of the participant roster until
    /// the user names them.
    var isPlaceholder: Bool { self == .others || label.hasPrefix(Self.numberedPrefix) }
}

struct TranscriptSegment: Codable, Sendable {
    let start: Double
    let end: Double
    let text: String
    let speaker: Speaker

    var timestamp: String { ElapsedTime.clock(Int(start.rounded())) }

    func relabeled(_ speaker: Speaker) -> TranscriptSegment {
        TranscriptSegment(start: start, end: end, text: text, speaker: speaker)
    }
}
