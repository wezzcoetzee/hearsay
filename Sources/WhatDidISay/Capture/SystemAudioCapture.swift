import Foundation
import AVFoundation
import ScreenCaptureKit

final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var sessionStarted = false
    private var finalizeResumed = false
    private let queue = DispatchQueue(label: "com.wcoetzee.whatdidisay.systemaudio")
    private let levels: AudioLevelSink

    init(levels: AudioLevelSink) {
        self.levels = levels
        super.init()
    }

    func start(writingTo url: URL, targetBundleID: String?) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter: SCContentFilter
        if let targetBundleID,
           let app = content.applications.first(where: { $0.bundleIdentifier == targetBundleID }) {
            filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        // An unfragmented m4a has no index until `finishWriting`, so a crash mid-call
        // would leave it unreadable. Fragments keep everything up to the last one playable.
        writer.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw CaptureError.writerSetupFailed }
        writer.add(input)
        self.writer = writer
        self.input = input
        self.sessionStarted = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        self.stream = stream
        try await stream.startCapture()
    }

    func stop() async {
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }

        await withCheckedContinuation { continuation in
            queue.async {
                self.finalizeResumed = false
                self.input?.markAsFinished()
                let finish: @Sendable () -> Void = {
                    guard !self.finalizeResumed else { return }
                    self.finalizeResumed = true
                    self.writer = nil
                    self.input = nil
                    self.sessionStarted = false
                    continuation.resume()
                }
                if let writer = self.writer, writer.status == .writing {
                    writer.finishWriting { self.queue.async(execute: finish) }
                    self.queue.asyncAfter(deadline: .now() + 8, execute: finish)
                } else {
                    finish()
                }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        levels.submitSystem(AudioLevel.level(of: sampleBuffer))

        guard let writer, let input else { return }

        if writer.status == .unknown {
            let start = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startWriting()
            writer.startSession(atSourceTime: start)
            sessionStarted = true
        }

        guard sessionStarted, writer.status == .writing, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("SystemAudioCapture stopped with error: \(error.localizedDescription)")
    }

    enum CaptureError: LocalizedError {
        case noDisplay
        case writerSetupFailed

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "No display available for system audio capture."
            case .writerSetupFailed: return "Could not set up the audio file writer."
            }
        }
    }
}
