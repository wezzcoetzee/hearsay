import Foundation

enum TranscriptMerger {
    static func merge(_ tracks: [TranscriptSegment]...) -> [TranscriptSegment] {
        tracks
            .flatMap { $0 }
            .sorted { lhs, rhs in
                lhs.start != rhs.start ? lhs.start < rhs.start : lhs.end < rhs.end
            }
    }
}
