import Testing

@testable import Hearsay

@Suite struct RosterTests {
    @Test func voicesAppearOnceInSpeakingOrderWithTheirOpeningLine() {
        let voices = RosterReview.voices(in: [
            makeSegment(0, "hello", .others),
            makeSegment(1, "hi back", .me),
            makeSegment(2, "still me", .me),
        ])
        #expect(voices.map(\.label) == ["Others", "Me"])
        #expect(voices.map(\.sample) == ["hello", "hi back"])
    }

    @Test func onlyPlaceholderVoicesNeedNaming() {
        let voices = RosterReview.voices(in: [
            makeSegment(0, "hi", .me),
            makeSegment(1, "hey", .numbered(1)),
        ])
        #expect(voices.map(\.suggestion) == ["Me", ""])
        #expect(voices.map(\.isPlaceholder) == [false, true])
    }

    @Test func namingAVoiceRelabelsOnlyThatVoice() {
        let roster = ReviewedRoster(voices: [ReviewedVoice(label: "Speaker 2", name: "Ada")], others: [])
        let out = roster.apply(to: [
            makeSegment(0, "hi", .numbered(0)),
            makeSegment(1, "hey", .numbered(1)),
        ])
        #expect(out.map(\.speaker.label) == ["Speaker 1", "Ada"])
    }

    @Test func participantsAreNamedVoicesThenEveryoneElse() {
        let roster = ReviewedRoster(
            voices: [
                ReviewedVoice(label: "Me", name: "Me"),
                ReviewedVoice(label: "Speaker 2", name: "Ada"),
                ReviewedVoice(label: "Speaker 3", name: ""),
            ],
            others: ["Grace"]
        )
        #expect(roster.participants == ["Me", "Ada", "Grace"])
    }

    @Test func aVoiceLeftAsAPlaceholderIsNotAParticipant() {
        let roster = ReviewedRoster(voices: [ReviewedVoice(label: "Others", name: "Others")], others: [])
        #expect(roster.participants.isEmpty)
    }

    @Test func unreviewedKeepsVoiceGuessesButNotScreenNames() {
        let review = RosterReview(
            voices: [
                VoiceCandidate(label: "Me", suggestion: "Me", sample: "hi"),
                VoiceCandidate(label: "Speaker 2", suggestion: "", sample: "hey"),
            ],
            others: ["General"]
        )
        #expect(review.unreviewed.participants == ["Me"])
    }

    private let call = ["Me", "Speaker 1", "Speaker 2"].map { VoiceCandidate(label: $0, suggestion: "", sample: "") }

    @Test func aVoiceMergesIntoTheNearestCallVoiceAboveIt() {
        #expect(RosterReview.mergeTarget(for: 2, in: call, merged: []) == 1)
        // Speaker 1 has no call voice above it, so it looks below; never into Me.
        #expect(RosterReview.mergeTarget(for: 1, in: call, merged: []) == 2)
        #expect(RosterReview.mergeTarget(for: 0, in: call, merged: []) == nil)
        #expect(RosterReview.mergeTarget(for: 1, in: call, merged: [2]) == nil)
    }

    @Test func aMergedVoiceTakesItsTargetsNameOrLabel() {
        let named = RosterReview.reviewed(call, names: ["Me", "Richard D", ""], mergedInto: [2: 1])
        #expect(named.map(\.name) == ["Me", "Richard D", "Richard D"])

        let unnamed = RosterReview.reviewed(call, names: ["Me", "", ""], mergedInto: [2: 1])
        #expect(unnamed.map(\.name) == ["Me", "", "Speaker 1"])
    }

    @Test func mergingTwoVoicesPutsAllTheirLinesUnderOneName() {
        let voices = RosterReview.reviewed(call, names: ["Me", "Richard D", ""], mergedInto: [2: 1])
        let roster = ReviewedRoster(voices: voices, others: [])
        let out = roster.apply(to: [makeSegment(0, "a", .numbered(0)), makeSegment(1, "b", .numbered(1))])
        #expect(out.map(\.speaker.label) == ["Richard D", "Richard D"])
        #expect(roster.participants == ["Me", "Richard D"])
    }
}
