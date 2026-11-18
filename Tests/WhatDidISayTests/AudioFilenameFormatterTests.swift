import Foundation
import Testing
@testable import WhatDidISay

@Suite struct AudioFilenameFormatterTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    @Test @MainActor func defaultFormatMatchesLegacyOutput() {
        let out = AudioFilenameFormatter.render(
            format: Settings.defaultAudioFilenameFormat,
            date: date, source: .slack, track: "system")
        #expect(out == "\(MarkdownWriter.fileTimestamp(date)) Slack Huddle system")
    }

    @Test func customFormatSubstitutesTokens() {
        let out = AudioFilenameFormatter.render(
            format: "{source}-{track}", date: date, source: .teams, track: "mic")
        #expect(out == "Teams Call-mic")
    }

    @Test func unknownTokensPassThroughLiterally() {
        let out = AudioFilenameFormatter.render(
            format: "{foo} {track}", date: date, source: .slack, track: "system")
        #expect(out == "{foo} system")
    }

    @Test func sanitizesPathSeparators() {
        let out = AudioFilenameFormatter.render(
            format: "a/b:c {track}", date: date, source: .slack, track: "mic")
        #expect(out == "abc mic")
    }

    @Test func emptyFormatFallsBackToTrack() {
        let system = AudioFilenameFormatter.render(format: "", date: date, source: .slack, track: "system")
        let mic = AudioFilenameFormatter.render(format: "", date: date, source: .slack, track: "mic")
        #expect(system == "system")
        #expect(mic == "mic")
        #expect(system != mic)
    }

    @Test func whitespaceOnlyFormatFallsBackToTrack() {
        let out = AudioFilenameFormatter.render(format: "   ", date: date, source: .slack, track: "system")
        #expect(out == "system")
    }

    @Test func missingTrackTokenAppendsTrackForDistinctNames() {
        let system = AudioFilenameFormatter.render(format: "{date}", date: date, source: .slack, track: "system")
        let mic = AudioFilenameFormatter.render(format: "{date}", date: date, source: .slack, track: "mic")
        #expect(system.hasSuffix(" system"))
        #expect(mic.hasSuffix(" mic"))
        #expect(system != mic)
    }
}
