import Foundation
import Testing

@testable import WhatDidISay

@Suite struct MarkdownWriterTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func metadata(
        source: RecordingSource = .slack,
        duration: TimeInterval = 125,
        participants: [String] = [],
        topic: String? = nil
    ) -> NoteMetadata {
        NoteMetadata(date: date, source: source, duration: duration, participants: participants, topic: topic)
    }

    private func seg(_ start: Double, _ text: String, _ speaker: Speaker) -> TranscriptSegment {
        TranscriptSegment(start: start, end: start + 1, text: text, speaker: speaker)
    }

    @Test func rendersTranscriptLinesWithTimestampAndSpeaker() {
        let out = MarkdownWriter.render(
            segments: [seg(0, "hi there", .me), seg(65, "hello", .others)],
            metadata: metadata(),
            summary: nil
        )
        #expect(out.contains("## Transcript"))
        #expect(out.contains("**[00:00] Me:** hi there"))
        #expect(out.contains("**[01:05] Others:** hello"))
    }

    @Test func emptySegmentsRenderPlaceholder() {
        let out = MarkdownWriter.render(segments: [], metadata: metadata(), summary: nil)
        #expect(out.contains("_No speech detected._"))
    }

    @Test func summaryIncludedWhenNonEmpty() {
        let out = MarkdownWriter.render(segments: [], metadata: metadata(), summary: "Key points.")
        #expect(out.contains("## Summary\nKey points."))
    }

    @Test func summaryOmittedWhenNilOrEmpty() {
        let none = MarkdownWriter.render(segments: [], metadata: metadata(), summary: nil)
        let empty = MarkdownWriter.render(segments: [], metadata: metadata(), summary: "")
        #expect(!none.contains("## Summary"))
        #expect(!empty.contains("## Summary"))
    }

    @Test func titleContainsSourceDisplayName() {
        let out = MarkdownWriter.render(segments: [], metadata: metadata(source: .teams), summary: nil)
        #expect(out.contains("# Teams Call — "))
    }

    @Test func topicTitlesTheNoteAndLandsInFrontMatter() {
        let out = MarkdownWriter.render(segments: [], metadata: metadata(topic: "Weekly goals"), summary: nil)
        #expect(out.contains("source: \"Slack Huddle\"\ntopic: \"Weekly goals\"\nparticipants:"))
        #expect(out.contains("# Weekly goals — "))
    }

    @Test func fileNameIsDateSourceTopic() {
        let stamp = MarkdownWriter.fileTimestamp(date)
        #expect(MarkdownWriter.fileName(metadata()) == "\(stamp) Slack Huddle")
        #expect(MarkdownWriter.fileName(metadata(topic: "Q3: plan / review.")) == "\(stamp) Slack Huddle - Q3 plan review")
    }

    @Test func durationRoundsToWholeMinutes() {
        let out = MarkdownWriter.render(segments: [], metadata: metadata(duration: 125), summary: nil)
        #expect(out.contains("duration: 2m"))
    }

    @Test func participantsDefaultToMeWhenEmpty() {
        let out = MarkdownWriter.render(segments: [], metadata: metadata(participants: []), summary: nil)
        #expect(out.contains("participants: [\"Me\"]"))
    }

    @Test func participantsRenderedAsQuotedList() {
        let out = MarkdownWriter.render(
            segments: [],
            metadata: metadata(participants: ["Ada", "Grace"]),
            summary: nil
        )
        #expect(out.contains("participants: [\"Ada\", \"Grace\"]"))
    }

    @Test func participantNamesWithQuotesAreEscaped() {
        let out = MarkdownWriter.render(
            segments: [],
            metadata: metadata(participants: ["A \"B\" C"]),
            summary: nil
        )
        #expect(out.contains(#"participants: ["A \"B\" C"]"#))
    }

    @Test func topicWithColonAndQuotesIsEscapedInFrontMatter() {
        let out = MarkdownWriter.render(
            segments: [],
            metadata: metadata(topic: #"Q3: the "big" plan"#),
            summary: nil
        )
        #expect(out.contains(#"topic: "Q3: the \"big\" plan""#))
    }

    @Test func writingTwiceKeepsBothNotes() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = try MarkdownWriter.write("one", metadata: metadata(), to: folder)
        let second = try MarkdownWriter.write("two", metadata: metadata(), to: folder)

        #expect(second.lastPathComponent == first.deletingPathExtension().lastPathComponent + " (2).md")
        #expect(try String(contentsOf: first, encoding: .utf8) == "one")
        #expect(try String(contentsOf: second, encoding: .utf8) == "two")
    }

    @Test func frontMatterIsDelimited() {
        let out = MarkdownWriter.render(segments: [], metadata: metadata(), summary: nil)
        #expect(out.hasPrefix("---\n"))
        #expect(out.contains("\n---\n"))
        #expect(out.contains("source: \"Slack Huddle\""))
    }
}
