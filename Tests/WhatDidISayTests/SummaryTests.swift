import Foundation
import Testing
@testable import WhatDidISay

@Suite struct SummaryTests {
    @Test func transcriptTextFormatsEachSegmentWithTimestampAndSpeaker() {
        let text = Summary.transcriptText([
            makeSegment(0, "hi there", .me),
            makeSegment(65, "hello", .others)
        ])
        #expect(text == "[00:00] Me: hi there\n[01:05] Others: hello")
    }

    @Test func transcriptTextIsEmptyForNoSegments() {
        #expect(Summary.transcriptText([]).isEmpty)
    }

    @Test func promptEmbedsTranscriptAndAsksForActionItems() {
        let prompt = Summary.prompt(for: "some transcript")
        #expect(prompt.contains("Transcript:\nsome transcript"))
        #expect(prompt.contains("## Action items"))
    }
}
