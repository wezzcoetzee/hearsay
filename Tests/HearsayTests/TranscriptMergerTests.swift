import Testing

@testable import Hearsay

@Suite struct TranscriptMergerTests {
    private func seg(_ start: Double, _ end: Double, _ text: String, _ speaker: Speaker = .me) -> TranscriptSegment {
        TranscriptSegment(start: start, end: end, text: text, speaker: speaker)
    }

    @Test func mergeIsEmptyForNoTracks() {
        #expect(TranscriptMerger.merge().isEmpty)
    }

    @Test func mergeSortsByStart() {
        let merged = TranscriptMerger.merge(
            [seg(2, 3, "second")],
            [seg(0, 1, "first")]
        )
        #expect(merged.map(\.text) == ["first", "second"])
    }

    @Test func mergeBreaksStartTiesByEnd() {
        let merged = TranscriptMerger.merge([
            seg(1, 5, "longer"),
            seg(1, 2, "shorter"),
        ])
        #expect(merged.map(\.text) == ["shorter", "longer"])
    }

    @Test func mergeInterleavesMultipleTracks() {
        let merged = TranscriptMerger.merge(
            [seg(0, 1, "a", .me), seg(4, 5, "c", .me)],
            [seg(2, 3, "b", .others)]
        )
        #expect(merged.map(\.text) == ["a", "b", "c"])
        #expect(merged.map(\.speaker) == [.me, .others, .me])
    }
}
