import Foundation
import Testing

@testable import WhatDidISay

@Suite struct DiarizerAssignmentTests {
    @Test func labelsSegmentsByTheSpanCoveringTheirMidpoint() {
        let segments = [makeSegment(0, "a", .others), makeSegment(10, "b", .others)]
        let spans = [SpeakerSpan(start: 0, end: 2, speakerId: 0), SpeakerSpan(start: 9, end: 12, speakerId: 1)]
        let out = Diarizer.assignSpeakers(segments, spans: spans)
        #expect(out.map(\.speaker) == [Speaker.numbered(0), Speaker.numbered(1)])
    }

    @Test func segmentInAGapGoesToTheNearestSpan() {
        // Midpoint 5.5: 0.5s after speaker 0 ends, 2.5s before speaker 1 starts.
        let segments = [makeSegment(5, "between", .others)]
        let spans = [SpeakerSpan(start: 0, end: 5, speakerId: 0), SpeakerSpan(start: 8, end: 12, speakerId: 1)]
        #expect(Diarizer.assignSpeakers(segments, spans: spans).first?.speaker == Speaker.numbered(0))
    }

    @Test func unknownSpeakersAreIgnored() {
        let segments = [makeSegment(0, "a", .others)]
        let spans = [SpeakerSpan(start: 0, end: 2, speakerId: -1)]
        #expect(Diarizer.assignSpeakers(segments, spans: spans).first?.speaker == .others)
    }
}
