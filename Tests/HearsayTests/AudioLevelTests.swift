import AVFoundation
import Foundation
import Testing

@testable import Hearsay

@Suite struct AudioLevelTests {
    @Test func silenceReadsAsZero() {
        #expect(AudioLevel.normalized(rms: 0) == 0)
    }

    @Test func anythingBelowTheFloorReadsAsZero() {
        let belowFloor = pow(10, (AudioLevel.floorDecibels - 1) / 20)
        #expect(AudioLevel.normalized(rms: belowFloor) == 0)
    }

    @Test func fullScaleReadsAsOne() {
        #expect(AudioLevel.normalized(rms: 1) == 1)
    }

    @Test func louderInputReadsHigher() {
        let quiet = AudioLevel.normalized(rms: 0.01)
        let loud = AudioLevel.normalized(rms: 0.5)
        #expect(quiet > 0)
        #expect(loud > quiet)
        #expect(loud < 1)
    }

    @Test func normalizedNeverExceedsOne() {
        #expect(AudioLevel.normalized(rms: 4) == 1)
    }

    @Test func toneInABufferReadsAboveTheSignalThreshold() throws {
        let buffer = try #require(Self.buffer(amplitude: 0.5, frames: 1024))
        let level = AudioLevel.level(of: buffer)
        #expect(level > AudioLevel.signalThreshold)
        #expect(level <= 1)
    }

    @Test func emptyBufferReadsAsZero() throws {
        let buffer = try #require(Self.buffer(amplitude: 0, frames: 1024))
        #expect(AudioLevel.level(of: buffer) == 0)
    }

    private static func buffer(amplitude: Float, frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
            let channel = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = frames
        for frame in 0..<Int(frames) {
            channel[0][frame] = amplitude * sin(Float(frame) * 0.1)
        }
        return buffer
    }
}

@Suite struct SilenceTrackerTests {
    private let start = Date(timeIntervalSince1970: 0)

    @Test func startsOutNotSilent() {
        let tracker = SilenceTracker()
        #expect(tracker.isSilent(at: start) == false)
    }

    @Test func quietForLessThanTheThresholdIsNotSilentYet() {
        var tracker = SilenceTracker(threshold: 8)
        tracker.record(level: 0, at: start)
        #expect(tracker.isSilent(at: start.addingTimeInterval(7)) == false)
    }

    @Test func quietPastTheThresholdIsSilent() {
        var tracker = SilenceTracker(threshold: 8)
        tracker.record(level: 0, at: start)
        #expect(tracker.isSilent(at: start.addingTimeInterval(8)))
    }

    @Test func signalClearsSilence() {
        var tracker = SilenceTracker(threshold: 8)
        tracker.record(level: 0, at: start)
        tracker.record(level: AudioLevel.signalThreshold, at: start.addingTimeInterval(9))
        #expect(tracker.isSilent(at: start.addingTimeInterval(9)) == false)
    }

    @Test func silenceRestartsTheClockAfterSignal() {
        var tracker = SilenceTracker(threshold: 8)
        tracker.record(level: 0.5, at: start)
        tracker.record(level: 0, at: start.addingTimeInterval(10))
        #expect(tracker.isSilent(at: start.addingTimeInterval(15)) == false)
        #expect(tracker.isSilent(at: start.addingTimeInterval(18)))
    }

    @Test func levelsBelowTheSignalThresholdCountAsQuiet() {
        var tracker = SilenceTracker(threshold: 8)
        tracker.record(level: AudioLevel.signalThreshold - 0.01, at: start)
        #expect(tracker.isSilent(at: start.addingTimeInterval(8)))
    }

    @Test func resetClearsPendingSilence() {
        var tracker = SilenceTracker(threshold: 8)
        tracker.record(level: 0, at: start)
        tracker.reset()
        #expect(tracker.isSilent(at: start.addingTimeInterval(100)) == false)
    }
}

@Suite struct AudioLevelSinkTests {
    @Test func drainReturnsThePeakSinceTheLastDrain() {
        let sink = AudioLevelSink()
        sink.submitMic(0.2)
        sink.submitMic(0.7)
        sink.submitMic(0.4)
        sink.submitSystem(0.3)
        let drained = sink.drain()
        #expect(drained.mic == 0.7)
        #expect(drained.system == 0.3)
    }

    @Test func drainClearsTheAccumulator() {
        let sink = AudioLevelSink()
        sink.submitMic(0.9)
        _ = sink.drain()
        #expect(sink.drain().mic == 0)
    }

    @Test func resetDropsPendingPeaks() {
        let sink = AudioLevelSink()
        sink.submitSystem(0.9)
        sink.reset()
        #expect(sink.drain().system == 0)
    }
}

@Suite @MainActor struct AudioLevelMonitorTests {
    private let start = Date(timeIntervalSince1970: 0)

    @Test func tickPublishesTheDrainedPeak() {
        let monitor = AudioLevelMonitor()
        monitor.sink.submitMic(0.8)
        monitor.tick(now: start)
        #expect(monitor.mic == 0.8)
    }

    @Test func meterFallsGraduallyWhenSoundStops() {
        let monitor = AudioLevelMonitor()
        monitor.sink.submitMic(1)
        monitor.tick(now: start)
        monitor.tick(now: start.addingTimeInterval(0.066))
        #expect(monitor.mic < 1)
        #expect(monitor.mic > 0)
    }

    @Test func meterNeverFallsBelowZero() {
        let monitor = AudioLevelMonitor()
        for step in 0..<40 {
            monitor.tick(now: start.addingTimeInterval(Double(step) * 0.066))
        }
        #expect(monitor.mic == 0)
    }

    @Test func sustainedQuietRaisesTheMicSilentFlag() {
        let monitor = AudioLevelMonitor()
        monitor.tick(now: start)
        #expect(monitor.micSilent == false)
        monitor.tick(now: start.addingTimeInterval(30))
        #expect(monitor.micSilent)
    }

    @Test func soundClearsTheMicSilentFlag() {
        let monitor = AudioLevelMonitor()
        monitor.tick(now: start)
        monitor.tick(now: start.addingTimeInterval(30))
        monitor.sink.submitMic(0.5)
        monitor.tick(now: start.addingTimeInterval(31))
        #expect(monitor.micSilent == false)
    }

    @Test func stopClearsEverything() {
        let monitor = AudioLevelMonitor()
        monitor.sink.submitMic(1)
        monitor.tick(now: start)
        monitor.tick(now: start.addingTimeInterval(30))
        monitor.stop()
        #expect(monitor.mic == 0)
        #expect(monitor.system == 0)
        #expect(monitor.micSilent == false)
    }
}
