import AVFoundation
import ObjCExceptionCatcher
import Testing

@Suite struct ObjCExceptionTests {
    /// AVAudioEngine reports a bad tap by raising. A second tap on the same bus raises the
    /// same way a stale input format does, without needing a microphone.
    @Test func anAudioEngineRaiseBecomesAThrownError() throws {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        player.installTap(onBus: 0, bufferSize: 4096, format: nil) { _, _ in }
        defer { player.removeTap(onBus: 0) }

        #expect(throws: (any Error).self) {
            try ObjCException.catching {
                player.installTap(onBus: 0, bufferSize: 4096, format: nil) { _, _ in }
            }
        }
    }

    @Test func aBlockThatDoesNotRaiseRunsOnce() throws {
        var runs = 0
        try ObjCException.catching { runs += 1 }
        #expect(runs == 1)
    }
}
