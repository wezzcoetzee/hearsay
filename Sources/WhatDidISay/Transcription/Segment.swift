import Foundation

struct Speaker: Equatable, Sendable {
    let label: String

    static let me = Speaker(label: "Me")
    static let others = Speaker(label: "Others")
    static func numbered(_ id: Int) -> Speaker { Speaker(label: "Speaker \(id + 1)") }
}

struct TranscriptSegment: Sendable {
    let start: Double
    let end: Double
    let text: String
    let speaker: Speaker

    var timestamp: String {
        let total = Int(start.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    func relabeled(_ speaker: Speaker) -> TranscriptSegment {
        TranscriptSegment(start: start, end: end, text: text, speaker: speaker)
    }
}
