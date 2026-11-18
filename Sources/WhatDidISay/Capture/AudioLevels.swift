import AVFoundation
import Accelerate
import CoreMedia
import Foundation

/// Loudness maths shared by both capture paths: raw audio in, 0...1 meter reading out.
enum AudioLevel {
    /// Anything quieter than this reads as silence on the meter.
    static let floorDecibels: Float = -60

    /// Reading above which we believe a channel is genuinely picking up sound.
    static let signalThreshold: Float = 0.06

    static func normalized(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        guard decibels > floorDecibels else { return 0 }
        return min(1, (decibels - floorDecibels) / -floorDecibels)
    }

    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frames = vDSP_Length(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0, channelCount > 0 else { return 0 }

        var total: Float = 0
        for channel in 0..<channelCount {
            var meanSquare: Float = 0
            vDSP_measqv(channels[channel], 1, &meanSquare, frames)
            total += meanSquare
        }
        return normalized(rms: sqrt(total / Float(channelCount)))
    }

    static func level(of sampleBuffer: CMSampleBuffer) -> Float {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
            asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
            asbd.mBitsPerChannel == 32
        else { return 0 }

        let channelCount = max(1, Int(asbd.mChannelsPerFrame))
        let list = AudioBufferList.allocate(maximumBuffers: channelCount)
        defer { free(list.unsafeMutablePointer) }

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: list.unsafeMutablePointer,
            bufferListSize: AudioBufferList.sizeInBytes(maximumBuffers: channelCount),
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return 0 }

        var total: Float = 0
        var counted = 0
        for buffer in list {
            guard let data = buffer.mData else { continue }
            let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard frames > 0 else { continue }
            var meanSquare: Float = 0
            vDSP_measqv(data.assumingMemoryBound(to: Float.self), 1, &meanSquare, vDSP_Length(frames))
            total += meanSquare
            counted += 1
        }
        guard counted > 0 else { return 0 }
        return normalized(rms: sqrt(total / Float(counted)))
    }
}

/// Tracks how long a channel has been quiet, so the UI can say so rather than
/// showing a confidently empty meter.
struct SilenceTracker {
    let threshold: TimeInterval

    private var quietSince: Date?

    init(threshold: TimeInterval = 8) {
        self.threshold = threshold
    }

    mutating func record(level: Float, at now: Date) {
        if level >= AudioLevel.signalThreshold {
            quietSince = nil
        } else if quietSince == nil {
            quietSince = now
        }
    }

    func isSilent(at now: Date) -> Bool {
        guard let quietSince else { return false }
        return now.timeIntervalSince(quietSince) >= threshold
    }

    mutating func reset() {
        quietSince = nil
    }
}

/// Hand-off point between the audio capture threads and the main actor. Capture
/// threads push peaks in; the monitor drains them at display rate.
final class AudioLevelSink: @unchecked Sendable {
    private let lock = NSLock()
    private var mic: Float = 0
    private var system: Float = 0

    func submitMic(_ level: Float) {
        lock.lock()
        mic = max(mic, level)
        lock.unlock()
    }

    func submitSystem(_ level: Float) {
        lock.lock()
        system = max(system, level)
        lock.unlock()
    }

    /// The loudest reading seen since the previous drain, clearing the accumulator.
    func drain() -> (mic: Float, system: Float) {
        lock.lock()
        defer {
            mic = 0
            system = 0
            lock.unlock()
        }
        return (mic, system)
    }

    func reset() {
        lock.lock()
        mic = 0
        system = 0
        lock.unlock()
    }
}

/// Publishes what the two capture streams are hearing right now: a smoothed
/// 0...1 level per channel, plus whether the mic has gone quiet for long enough to be
/// worth flagging. Call audio isn't flagged: a quiet far end is normal.
///
/// Values are only republished when they change, so a silent channel doesn't redraw
/// the meters fifteen times a second for the whole call.
@MainActor
final class AudioLevelMonitor: ObservableObject {
    @Published private(set) var mic: Float = 0
    @Published private(set) var system: Float = 0
    @Published private(set) var micSilent = false
    /// False while recording a source with no system track, so the UI can drop the
    /// meter rather than show one that will never move.
    @Published private(set) var tracksSystemAudio = true

    let sink = AudioLevelSink()

    /// How far a meter may fall in a single frame, so peaks decay instead of flickering.
    private let fallPerFrame: Float = 0.12
    private let frameInterval = Duration.milliseconds(66)

    private var micSilence = SilenceTracker()
    private var pump: Task<Void, Never>?

    func start(systemAudio: Bool) {
        stop()
        tracksSystemAudio = systemAudio
        let interval = frameInterval
        pump = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.tick(now: Date())
            }
        }
    }

    func stop() {
        pump?.cancel()
        pump = nil
        sink.reset()
        micSilence.reset()
        update(\.mic, to: 0)
        update(\.system, to: 0)
        update(\.micSilent, to: false)
        update(\.tracksSystemAudio, to: true)
    }

    func tick(now: Date) {
        let peaks = sink.drain()
        micSilence.record(level: peaks.mic, at: now)
        update(\.mic, to: smoothed(from: mic, toward: peaks.mic))
        update(\.system, to: smoothed(from: system, toward: peaks.system))
        update(\.micSilent, to: micSilence.isSilent(at: now))
    }

    private func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<AudioLevelMonitor, Value>, to value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    private func smoothed(from current: Float, toward peak: Float) -> Float {
        max(peak, current - fallPerFrame)
    }
}

#if DEBUG
    extension AudioLevelMonitor {
        /// Fixed meter readings for the screenshot catalog. Debug builds only.
        func stageForScreenshots(mic: Float, system: Float, micSilent: Bool = false, tracksSystemAudio: Bool = true) {
            self.mic = mic
            self.system = system
            self.micSilent = micSilent
            self.tracksSystemAudio = tracksSystemAudio
        }
    }
#endif
