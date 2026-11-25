import Testing

@testable import Hearsay

@Suite struct SegmentTests {
    @Test func timestampFormatsMinutesAndSeconds() {
        #expect(TranscriptSegment(start: 0, end: 1, text: "", speaker: .me).timestamp == "00:00")
        #expect(TranscriptSegment(start: 65, end: 70, text: "", speaker: .me).timestamp == "01:05")
        #expect(TranscriptSegment(start: 3599, end: 3600, text: "", speaker: .me).timestamp == "59:59")
    }

    @Test func timestampGrowsAnHourFieldOnLongCalls() {
        #expect(TranscriptSegment(start: 3600, end: 3601, text: "", speaker: .me).timestamp == "1:00:00")
        #expect(TranscriptSegment(start: 3912, end: 3913, text: "", speaker: .me).timestamp == "1:05:12")
    }

    @Test func timestampRoundsToNearestSecond() {
        #expect(TranscriptSegment(start: 59.6, end: 60, text: "", speaker: .me).timestamp == "01:00")
    }

    @Test func relabeledKeepsTimingAndTextButSwapsSpeaker() {
        let original = TranscriptSegment(start: 1, end: 2, text: "hello", speaker: .me)
        let relabeled = original.relabeled(.others)
        #expect(relabeled.start == 1)
        #expect(relabeled.end == 2)
        #expect(relabeled.text == "hello")
        #expect(relabeled.speaker == .others)
    }

    @Test func speakerLabels() {
        #expect(Speaker.me.label == "Me")
        #expect(Speaker.others.label == "Others")
        #expect(Speaker.numbered(0).label == "Speaker 1")
        #expect(Speaker.numbered(4).label == "Speaker 5")
    }
}
