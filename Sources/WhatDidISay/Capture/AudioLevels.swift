import Foundation
import Accelerate
import AVFoundation
import CoreMedia

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
              asbd.mBitsPerChannel == 32 else { return 0 }

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
/// 0...1 level per channel, plus whether a channel has gone quiet for long
/// enough to be worth flagging.
@MainActor
final class AudioLevelMonitor: ObservableObject {
    @Published private(set) var mic: Float = 0
    @Published private(set) var system: Float = 0
    @Published private(set) var micSilent = false
    @Published private(set) var systemSilent = false

    let sink = AudioLevelSink()

    /// How far a meter may fall in a single frame, so peaks decay instead of flickering.
    private let fallPerFrame: Float = 0.12
    private let frameInterval = Duration.milliseconds(66)

    private var micSilence = SilenceTracker()
    private var systemSilence = SilenceTracker()
    private var pump: Task<Void, Never>?

    func start() {
        stop()
        sink.reset()
        micSilence.reset()
        systemSilence.reset()
        pump = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.frameInterval ?? .milliseconds(66))
                guard !Task.isCancelled else { return }
                self?.tick(now: Date())
            }
        }
    }

    func stop() {
        pump?.cancel()
        pump = nil
        sink.reset()
        mic = 0
        system = 0
        micSilent = false
        systemSilent = false
        micSilence.reset()
        systemSilence.reset()
    }

    func tick(now: Date) {
        let peaks = sink.drain()
        mic = smoothed(from: mic, toward: peaks.mic)
        system = smoothed(from: system, toward: peaks.system)

        micSilence.record(level: peaks.mic, at: now)
        systemSilence.record(level: peaks.system, at: now)
        micSilent = micSilence.isSilent(at: now)
        systemSilent = systemSilence.isSilent(at: now)
    }

    private func smoothed(from current: Float, toward peak: Float) -> Float {
        max(peak, current - fallPerFrame)
    }
}
