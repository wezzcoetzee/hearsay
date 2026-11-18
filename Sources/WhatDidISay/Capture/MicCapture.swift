import Foundation
import AVFoundation
import ObjCExceptionCatcher

/// Writes tap buffers to the mic file from the audio thread, while `close()` may run on
/// the main one. Buffers in another format than the file (the input device changed
/// mid-call) are converted to it, so the recording continues in one consistent file.
final class MicFileWriter: @unchecked Sendable {
    enum WriteError: LocalizedError {
        case unsupportedFormat
        case noInput

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: return "The microphone changed to a format that can't be recorded."
            case .noInput: return "No microphone input is available."
            }
        }
    }

    private let lock = NSLock()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private let onFailure: @Sendable (Error) -> Void

    /// `onFailure` hears about every failed write; the caller decides how often to pass it on.
    init(file: AVAudioFile, onFailure: @escaping @Sendable (Error) -> Void) {
        self.file = file
        self.onFailure = onFailure
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        let failure: Error? = lock.withLock {
            guard let file else { return nil }
            do {
                try file.write(from: try converted(buffer, to: file.processingFormat))
                return nil
            } catch {
                return error
            }
        }
        if let failure { onFailure(failure) }
    }

    func close() {
        lock.withLock {
            file = nil
            converter = nil
        }
    }

    private func converted(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard buffer.format != format else { return buffer }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { throw WriteError.unsupportedFormat }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw WriteError.unsupportedFormat
        }

        nonisolated(unsafe) var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error { throw conversionError ?? WriteError.unsupportedFormat }
        return output
    }
}

@MainActor
final class MicCapture {
    /// Called at most once per `start`, from any thread, when capture stops writing audio
    /// unexpectedly (the input couldn't restart after a device change, or writes fail).
    var onInterrupted: (@Sendable (Error) -> Void)?

    /// Replaced on every `start`. An engine kept from the last call can still report the
    /// input format from back then, while a call app has since switched the device (a
    /// headset going into call mode), and tapping that stale format raises.
    private var engine = AVAudioEngine()
    private let levels: AudioLevelSink
    private let reporter = InterruptionReporter()
    private var writer: MicFileWriter?
    private var configurationObserver: NSObjectProtocol?
    private var isRunning = false

    init(levels: AudioLevelSink) {
        self.levels = levels
    }

    func start(writingTo url: URL) throws {
        engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        reporter.arm(onInterrupted)
        writer = MicFileWriter(file: file, onFailure: { [reporter] in reporter.report($0) })

        do {
            try run(inputFormat: format)
        } catch {
            writer = nil
            throw error
        }
        isRunning = true
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartAfterConfigurationChange() }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        reporter.arm(nil)
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        writer?.close()
        writer = nil
    }

    private func run(inputFormat: AVAudioFormat) throws {
        // Tapping a format without a sample rate (no input device) raises and crashes.
        guard let writer, inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw MicFileWriter.WriteError.noInput
        }
        let input = engine.inputNode
        // A format that doesn't match the device raises rather than throws. Uncaught, it
        // skipped the rest of `RecordingController.start`: call audio kept recording, the
        // menu never showed it, and the next actor check crashed the app.
        try ObjCException.catching {
            input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [levels] buffer, _ in
                writer.write(buffer)
                levels.submitMic(AudioLevel.level(of: buffer))
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            // A tap left behind makes the next installTap raise and crash the app.
            input.removeTap(onBus: 0)
            throw error
        }
    }

    /// The engine has stopped because the input device or its format changed (AirPods
    /// connecting, say). Retap with the new format; the file keeps its original one.
    private func restartAfterConfigurationChange() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        do {
            try run(inputFormat: engine.inputNode.outputFormat(forBus: 0))
        } catch MicFileWriter.WriteError.noInput {
            // Mid route switch the input briefly has no format; the change that
            // follows once it settles brings the real one and restarts the tap.
        } catch {
            reporter.report(error)
        }
    }
}
