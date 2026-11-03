import Testing
import AVFoundation
@testable import WhatDidISay

@Suite struct MicFileWriterTests {
    private func makeFile(sampleRate: Double, channels: AVAudioChannelCount) throws -> (AVAudioFile, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mic-\(UUID().uuidString).caf")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels))
        return (try AVAudioFile(forWriting: url, settings: format.settings), url)
    }

    private func tone(sampleRate: Double, channels: AVAudioChannelCount, frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(frames) {
                buffer.floatChannelData![channel][frame] = sin(Float(frame) * 0.05) * 0.5
            }
        }
        return buffer
    }

    @Test func buffersInTheFileFormatAreWrittenAsIs() throws {
        let (file, url) = try makeFile(sampleRate: 48_000, channels: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = MicFileWriter(file: file) { error in Issue.record(error) }

        writer.write(try tone(sampleRate: 48_000, channels: 1, frames: 4800))
        writer.close()

        #expect(try AVAudioFile(forReading: url).length == 4800)
    }

    @Test func buffersFromANewInputDeviceAreConvertedToTheFileFormat() throws {
        let (file, url) = try makeFile(sampleRate: 48_000, channels: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = MicFileWriter(file: file) { error in Issue.record(error) }

        // Built-in mic at 48 kHz, then AirPods at 16 kHz: the file must stay at 48 kHz.
        writer.write(try tone(sampleRate: 48_000, channels: 1, frames: 4800))
        for _ in 0..<5 {
            writer.write(try tone(sampleRate: 16_000, channels: 1, frames: 1600))
        }
        writer.close()

        let written = try AVAudioFile(forReading: url)
        #expect(written.processingFormat.sampleRate == 48_000)
        // 0.1 s + 0.5 s of audio; the resampler holds back a few frames of latency.
        #expect(abs(Int(written.length) - 28_800) < 600)
    }

    @Test func stereoInputIsDownmixedToAMonoFile() throws {
        let (file, url) = try makeFile(sampleRate: 48_000, channels: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = MicFileWriter(file: file) { error in Issue.record(error) }

        // The converter holds back up to one block, so judge the total over many buffers.
        for _ in 0..<10 {
            writer.write(try tone(sampleRate: 48_000, channels: 2, frames: 4800))
        }
        writer.close()

        let written = try AVAudioFile(forReading: url)
        #expect(written.processingFormat.channelCount == 1)
        #expect(abs(Int(written.length) - 48_000) < 4_800, "length \(written.length)")
    }

    @Test func writesAfterCloseAreIgnored() throws {
        let (file, url) = try makeFile(sampleRate: 48_000, channels: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = MicFileWriter(file: file) { error in Issue.record(error) }

        writer.close()
        writer.write(try tone(sampleRate: 48_000, channels: 1, frames: 4800))

        #expect(try AVAudioFile(forReading: url).length == 0)
    }
}
