import Foundation
import Testing
@testable import WhatDidISay

@Suite @MainActor struct TranscriptBuilderTests {
    private let system = URL(fileURLWithPath: "/tmp/system.m4a")
    private let mic = URL(fileURLWithPath: "/tmp/mic.caf")

    private func builder(_ transcriber: FakeTranscriber, _ diarizer: FakeDiarizer = FakeDiarizer()) -> TranscriptBuilder {
        TranscriptBuilder(transcriber: transcriber, diarizer: diarizer)
    }

    @Test func mergesBothTracksSortedByStart() async throws {
        let transcriber = FakeTranscriber(
            others: [makeSegment(2, "theirs", .others)],
            mine: [makeSegment(0, "mine", .me)]
        )
        let out = try await builder(transcriber).build(system: system, mic: mic, model: "base", diarize: false)
        #expect(out.map(\.text) == ["mine", "theirs"])
    }

    @Test func leavesSpeakersUntouchedWhenDiarizeDisabled() async throws {
        let transcriber = FakeTranscriber(others: [makeSegment(0, "hi", .others)], mine: [])
        let diarizer = FakeDiarizer(spans: [SpeakerSpan(start: 0, end: 2, speakerId: 0)])
        let out = try await builder(transcriber, diarizer).build(system: system, mic: mic, model: "base", diarize: false)
        #expect(out.first?.speaker == .others)
    }

    @Test func assignsSpeakersWhenDiarizeEnabled() async throws {
        let transcriber = FakeTranscriber(others: [makeSegment(0, "hi", .others)], mine: [])
        let diarizer = FakeDiarizer(spans: [SpeakerSpan(start: 0, end: 2, speakerId: 0)])
        let out = try await builder(transcriber, diarizer).build(system: system, mic: mic, model: "base", diarize: true)
        #expect(out.first?.speaker == Speaker.numbered(0))
    }

    @Test func diarizationFailureKeepsOriginalSpeakers() async throws {
        let transcriber = FakeTranscriber(others: [makeSegment(0, "hi", .others)], mine: [])
        let diarizer = FakeDiarizer(shouldThrow: true)
        let out = try await builder(transcriber, diarizer).build(system: system, mic: mic, model: "base", diarize: true)
        #expect(out.first?.speaker == .others)
    }

    @Test func reportsTranscribingThenIdentifyingPhases() async throws {
        var phases: [TranscriptBuilder.Phase] = []
        let transcriber = FakeTranscriber(others: [makeSegment(0, "hi", .others)], mine: [])
        let diarizer = FakeDiarizer(spans: [SpeakerSpan(start: 0, end: 1, speakerId: 0)])
        _ = try await builder(transcriber, diarizer)
            .build(system: system, mic: mic, model: "base", diarize: true) { phases.append($0) }
        #expect(phases == [.transcribing, .identifyingSpeakers])
    }

    @Test func passesParticipantHintsToTranscriber() async throws {
        let transcriber = FakeTranscriber(others: [], mine: [])
        _ = try await builder(transcriber)
            .build(system: system, mic: mic, model: "base", diarize: false, hints: ["Ada Lovelace"])
        #expect(transcriber.receivedHints == ["Ada Lovelace"])
    }

    @Test func skipsIdentifyingPhaseWhenDiarizeDisabled() async throws {
        var phases: [TranscriptBuilder.Phase] = []
        let transcriber = FakeTranscriber(others: [], mine: [])
        _ = try await builder(transcriber)
            .build(system: system, mic: mic, model: "base", diarize: false) { phases.append($0) }
        #expect(phases == [.transcribing])
    }
}
