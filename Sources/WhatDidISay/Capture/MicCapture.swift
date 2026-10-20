import Foundation
import AVFoundation

final class MicCapture {
    private let engine = AVAudioEngine()
    private let levels: AudioLevelSink
    private var file: AVAudioFile?
    private var isRunning = false

    init(levels: AudioLevelSink) {
        self.levels = levels
    }

    func start(writingTo url: URL) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        self.file = file

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.file?.write(from: buffer)
            self.levels.submitMic(AudioLevel.level(of: buffer))
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            // A tap left behind makes the next installTap raise and crash the app.
            input.removeTap(onBus: 0)
            self.file = nil
            throw error
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
        isRunning = false
    }
}
