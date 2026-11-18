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

    @Test func promptAsksForATopicLine() {
        #expect(Summary.prompt(for: "x").contains("Topic:"))
    }

    @Test func topicLineIsSplitFromTheSummary() {
        let summary = NoteSummary(parsing: "**Topic: Jetstream weekly goals.**\n\n- Agreed scope")
        #expect(summary == NoteSummary(topic: "Jetstream weekly goals", markdown: "- Agreed scope"))
    }

    @Test func summaryWithoutATopicLineIsKeptWhole() {
        #expect(NoteSummary(parsing: "- Agreed scope\n") == NoteSummary(topic: nil, markdown: "- Agreed scope"))
    }

    private func claude(_ json: String, status: Int = 200) throws -> String {
        try ClaudeSummarizer.parse(Data(json.utf8), status: status)
    }

    private func failsWith(_ fragment: String, _ body: () throws -> String) {
        #expect {
            try body()
        } throws: { error in
            (error as? SummaryError)?.errorDescription?.contains(fragment) == true
        }
    }

    @Test func claudeSummaryIsTheTextBlocksWithoutThinking() throws {
        let text = try claude("""
            {"stop_reason":"end_turn","content":[
              {"type":"thinking","thinking":"hmm"},{"type":"text","text":"\\n- Point\\n"}]}
            """)
        #expect(text == "- Point")
    }

    @Test func claudeReplyWithoutATextBlockIsUnavailable() {
        failsWith("without any text") {
            try claude(#"{"stop_reason":"end_turn","content":[{"type":"thinking","thinking":"hmm"}]}"#)
        }
    }

    @Test func claudeRunningOutOfTokensIsUnavailableEvenWithPartialText() {
        failsWith("ran out of output tokens") {
            try claude(#"{"stop_reason":"max_tokens","content":[{"type":"text","text":"- Half a"}]}"#)
        }
    }

    @Test func claudeRefusalIsUnavailable() {
        failsWith("declined") { try claude(#"{"stop_reason":"refusal","content":[]}"#) }
    }

    @Test func claudeErrorsCarryTheApiMessage() {
        failsWith("401: invalid x-api-key") {
            try claude(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#, status: 401)
        }
        failsWith("returned 502") { try claude("<html>Bad gateway</html>", status: 502) }
    }

    @Test func ollamaEmptyResponseIsUnavailable() {
        failsWith("empty response") {
            try OllamaSummarizer.parse(Data(#"{"response":" \n"}"#.utf8), status: 200, model: "llama3.2")
        }
    }

    @Test func ollamaMissingModelSaysHowToPullIt() {
        failsWith("ollama pull llama3.2") {
            try OllamaSummarizer.parse(Data(), status: 404, model: "llama3.2")
        }
    }

    @Test func ollamaContextGrowsWithThePromptWithinBounds() {
        let context = OllamaSummarizer.contextLength(forPrompt:)
        #expect(context("short") == 4_096)
        #expect(context(String(repeating: "a", count: 35_000)) == 10_000 + 2_048)
        #expect(context(String(repeating: "a", count: 1_000_000)) == 32_768)
    }
}
