import Testing
@testable import WhatDidISay

@Suite struct RosterTests {
    @Test func voicesAppearOnceInSpeakingOrderWithTheirOpeningLine() {
        let voices = RosterReview.voices(in: [
            makeSegment(0, "hello", .others),
            makeSegment(1, "hi back", .me),
            makeSegment(2, "still me", .me)
        ])
        #expect(voices.map(\.label) == ["Others", "Me"])
        #expect(voices.map(\.sample) == ["hello", "hi back"])
    }

    @Test func onlyPlaceholderVoicesNeedNaming() {
        let voices = RosterReview.voices(in: [
            makeSegment(0, "hi", .me),
            makeSegment(1, "hey", .numbered(1))
        ])
        #expect(voices.map(\.suggestion) == ["Me", ""])
        #expect(voices.map(\.isPlaceholder) == [false, true])
    }

    @Test func namingAVoiceRelabelsOnlyThatVoice() {
        let roster = ReviewedRoster(voices: [ReviewedVoice(label: "Speaker 2", name: "Ada")], others: [])
        let out = roster.apply(to: [
            makeSegment(0, "hi", .numbered(0)),
            makeSegment(1, "hey", .numbered(1))
        ])
        #expect(out.map(\.speaker.label) == ["Speaker 1", "Ada"])
    }

    @Test func participantsAreNamedVoicesThenEveryoneElse() {
        let roster = ReviewedRoster(
            voices: [ReviewedVoice(label: "Me", name: "Me"),
                     ReviewedVoice(label: "Speaker 2", name: "Ada"),
                     ReviewedVoice(label: "Speaker 3", name: "")],
            others: ["Grace"]
        )
        #expect(roster.participants == ["Me", "Ada", "Grace"])
    }

    @Test func aVoiceLeftAsAPlaceholderIsNotAParticipant() {
        let roster = ReviewedRoster(voices: [ReviewedVoice(label: "Others", name: "Others")], others: [])
        #expect(roster.participants.isEmpty)
    }

    @Test func unreviewedKeepsEveryGuess() {
        let review = RosterReview(
            voices: [VoiceCandidate(label: "Me", suggestion: "Me", sample: "hi"),
                     VoiceCandidate(label: "Speaker 2", suggestion: "", sample: "hey")],
            others: ["Ada"]
        )
        #expect(review.unreviewed.participants == ["Me", "Ada"])
    }
}
