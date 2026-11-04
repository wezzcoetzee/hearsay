import AppKit
import Foundation

/// Watches whether a target app (Slack/Teams) is actively producing audio output.
/// While a huddle/call is live the app runs an output stream; when it ends the stream
/// stops. Unlike the microphone flag, this is not masked by our own recording.
///
/// Polls rather than listening: the app's audio processes come and go (a Meet tab's
/// helper spawns after the green room, an Electron helper can be replaced mid-call),
/// so each poll looks them up afresh. The call only counts as ended after output was
/// seen and then stayed silent for 12 seconds, so a call that hasn't started producing
/// audio yet is never cut short.
@MainActor
final class CallActivityMonitor {
    var onEnded: (() -> Void)?

    private static let pollInterval = Duration.seconds(2)
    private static let grace = Duration.seconds(12)
    private var pollTask: Task<Void, Never>?

    func start(bundleID: String) {
        guard #available(macOS 14.4, *), pollTask == nil else { return }
        pollTask = Task { [weak self] in
            let clock = ContinuousClock()
            var hasSeenOutput = false
            var silentSince: ContinuousClock.Instant?
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled, let self else { return }
                if self.isRunningOutput(bundleID: bundleID) {
                    hasSeenOutput = true
                    silentSince = nil
                } else if hasSeenOutput {
                    let since = silentSince ?? clock.now
                    silentSince = since
                    if clock.now - since >= Self.grace {
                        self.onEnded?()
                        return
                    }
                }
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func isRunningOutput(bundleID: String) -> Bool {
        guard #available(macOS 14.4, *),
            let path = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.bundleURL?.path
        else { return false }
        return AudioProcesses.isRunning(.output, inBundleAt: path)
    }
}
