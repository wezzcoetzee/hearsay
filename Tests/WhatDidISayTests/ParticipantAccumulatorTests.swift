import Testing

@testable import WhatDidISay

@Suite struct ParticipantAccumulatorTests {
    @Test func keepsEverythingForShortCalls() {
        var acc = ParticipantAccumulator()
        acc.record(["Ada Lovelace"])
        acc.record(["Grace Hopper"])
        #expect(Set(acc.resolved()) == ["Ada Lovelace", "Grace Hopper"])
    }

    @Test func dropsOneOffNoiseOnceEnoughSamplesSeen() {
        var acc = ParticipantAccumulator()
        acc.record(["Ada Lovelace", "Untitled"])
        acc.record(["Ada Lovelace"])
        acc.record(["Ada Lovelace", "Copilot"])
        #expect(acc.resolved() == ["Ada Lovelace"])
    }

    @Test func keepsNamesThatRecur() {
        var acc = ParticipantAccumulator()
        acc.record(["Ada Lovelace", "Grace Hopper"])
        acc.record(["Ada Lovelace", "Grace Hopper"])
        acc.record(["Ada Lovelace"])
        #expect(Set(acc.resolved()) == ["Ada Lovelace", "Grace Hopper"])
    }
}
