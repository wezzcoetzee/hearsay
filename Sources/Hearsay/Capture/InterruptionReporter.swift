import Foundation

/// Delivers at most one `onInterrupted` call per capture run, from whichever thread
/// notices the failure. Shared by `MicCapture` and `SystemAudioCapture`.
final class InterruptionReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (Error) -> Void)?

    /// Starts a run that reports to `handler`; `nil` silences it, e.g. once capture was stopped on purpose.
    func arm(_ handler: (@Sendable (Error) -> Void)?) {
        lock.withLock { self.handler = handler }
    }

    func report(_ error: Error) {
        let handler = lock.withLock {
            defer { self.handler = nil }
            return self.handler
        }
        handler?(error)
    }
}
