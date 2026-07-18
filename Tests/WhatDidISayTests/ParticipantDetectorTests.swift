import Testing
@testable import WhatDidISay

@Suite struct ParticipantDetectorFilterTests {
    @Test func keepsPlausibleNames() {
        let names = ParticipantDetector.filterNames(["Ada Lovelace", "Grace Hopper"])
        #expect(names == ["Ada Lovelace", "Grace Hopper"])
    }

    @Test func trimsWhitespace() {
        #expect(ParticipantDetector.filterNames(["  Ada Lovelace  "]) == ["Ada Lovelace"])
    }

    @Test func rejectsBlocklistedUIWords() {
        #expect(ParticipantDetector.filterNames(["Mute", "Leave", "Participants"]).isEmpty)
    }

    @Test func rejectsLowercaseStartedWords() {
        #expect(ParticipantDetector.filterNames(["ada lovelace"]).isEmpty)
    }

    @Test func rejectsNamesWithDigitsOrSymbols() {
        #expect(ParticipantDetector.filterNames(["Ada2", "Ada!", "Ada @ Home"]).isEmpty)
    }

    @Test func allowsApostrophesHyphensAndInitials() {
        let names = ParticipantDetector.filterNames(["O'Brien", "Jean-Luc Picard", "J.R.R. Tolkien"])
        #expect(names.contains("O'Brien"))
        #expect(names.contains("Jean-Luc Picard"))
        #expect(names.contains("J.R.R. Tolkien"))
    }

    @Test func rejectsTooShortOrTooLong() {
        let long = String(repeating: "Ab ", count: 20)
        #expect(ParticipantDetector.filterNames(["A", long]).isEmpty)
    }

    @Test func rejectsMoreThanThreeWords() {
        #expect(ParticipantDetector.filterNames(["Ada Byron King Lovelace"]).isEmpty)
    }

    @Test func deduplicatesRepeatedNames() {
        #expect(ParticipantDetector.filterNames(["Ada Lovelace", "Ada Lovelace"]) == ["Ada Lovelace"])
    }
}
