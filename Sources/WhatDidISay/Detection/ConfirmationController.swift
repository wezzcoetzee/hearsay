import AppKit
import Combine
import SwiftUI

/// Why a detected call can't simply be recorded: the recorder still holds the last
/// one, or the start just failed.
enum CallBlocker: Equatable {
    /// The participant review is open, waiting on the user. Recording is still offered:
    /// it parks that review under Needs Attention.
    case awaitingNames
    /// The last note is still being transcribed, summarized or written.
    case savingLastNote
    /// Start Recording was clicked but capture didn't start.
    case startFailed(String)

    var isFailure: Bool {
        if case .startFailed = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .awaitingNames: "Your last recording is waiting for names; you can name them later."
        case .savingLastNote: "The last recording is still being saved. You can record again once its note is ready."
        case .startFailed(let reason): reason
        }
    }
}

@MainActor
final class ConfirmationController: ObservableObject {
    @Published private(set) var pending: RecordingSource?
    @Published private(set) var countdown: Int = 0
    @Published private(set) var cloudActive = false
    /// Why the call can't be recorded right now (the last note is still saving), or
    /// `nil` when it can. The prompt still appears so auto-detect never looks broken.
    @Published private(set) var blocker: CallBlocker?
    /// The countdown holds while the pointer is over the prompt, so reading it or
    /// reaching for a button never races the dismissal.
    @Published var isPaused = false
    /// With VoiceOver on, nobody can be expected to reach the prompt in fifteen
    /// seconds, so it waits for an answer instead.
    @Published private(set) var waitsForAnswer = false

    var onConfirm: ((RecordingSource) -> Void)?
    /// Parks the recording waiting for names and records this call instead.
    var onNameLaterAndRecord: ((RecordingSource) -> Void)?
    var isCloudSummaryActive: (() -> Bool)?

    private var panel: NSPanel?
    private var timerTask: Task<Void, Never>?
    private let startSeconds = 15

    func present(source: RecordingSource, blocker: CallBlocker? = nil) {
        guard pending == nil else { return }
        pending = source
        countdown = startSeconds
        cloudActive = isCloudSummaryActive?() ?? false
        self.blocker = blocker
        isPaused = false
        // A failure is never dismissed for the user: it's the only sign the call
        // isn't being recorded.
        let assistive = NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled
        waitsForAnswer = assistive || blocker?.isFailure == true
        showPanel()
        // VoiceOver users can't reach a panel that never takes focus, so for them it
        // does. Everyone else keeps typing into the call undisturbed.
        if NSWorkspace.shared.isVoiceOverEnabled { panel?.makeKey() }
        Announcer.post(
            blocker.map {
                if case .startFailed(let reason) = $0 { return "\(source.displayName) not recorded. \(reason)" }
                return "\(source.displayName) detected. \($0.message)"
            }
                ?? "\(source.displayName) detected. Start recording?")
        guard !waitsForAnswer else { return }
        timerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                if !self.isPaused { self.countdown -= 1 }
            }
            self.dismiss()
        }
    }

    func confirm() { finish(start: true) }

    /// Follows the recorder while the prompt is up: a note that finishes saving turns
    /// "still being saved" into a normal offer, so the call isn't lost to a stale
    /// message.
    func refresh(blocker: CallBlocker?) {
        guard pending != nil, self.blocker != blocker else { return }
        if case .startFailed = self.blocker { return }
        self.blocker = blocker
    }

    /// Says so when Start Recording didn't work, since the prompt has already gone and
    /// the menu is usually closed.
    func presentFailure(source: RecordingSource, reason: String) {
        present(source: source, blocker: .startFailed(reason))
    }

    func nameLaterAndRecord() {
        let source = pending
        dismiss()
        if let source { onNameLaterAndRecord?(source) }
    }
    func dismiss() { finish(start: false) }

    /// Takes the prompt down when the call it's offering to record has already ended,
    /// so "Start Recording" can't begin capturing a call that's over.
    func withdraw(ifEndedBy bundleID: String?) {
        guard let pending else { return }
        if let bundleID, !pending.bundleIDs.contains(bundleID) { return }
        dismiss()
    }

    private func finish(start: Bool) {
        timerTask?.cancel()
        timerTask = nil
        let source = pending
        pending = nil
        panel?.orderOut(nil)
        panel = nil
        if start, blocker == nil, let source { onConfirm?(source) }
    }

    private func showPanel() {
        let hosting = NSHostingView(rootView: ConfirmationView(controller: self))
        // Sized to the content, so longer copy (the cloud note) is never clipped.
        let panel = NSPanel.floating(
            contentView: hosting,
            size: hosting.fittingSize,
            styleMask: [.titled])
        panel.title = "Call detected"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

struct ConfirmationView: View {
    @ObservedObject var controller: ConfirmationController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                // Red is kept for recording and errors: the source glyph is the accent
                // colour, and a failed start shows the error triangle.
                if case .startFailed = controller.blocker {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: controller.pending?.symbolName ?? "phone.fill")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.headline)
                Spacer()
                if !controller.waitsForAnswer {
                    // Once a second for fifteen seconds, so a rolling digit costs nothing.
                    Text(controller.isPaused ? "Paused" : "Closes in \(controller.countdown)s")
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(reduceMotion ? nil : .snappy, value: controller.countdown)
                }
            }
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                if let blocker = controller.blocker, blocker != .awaitingNames {
                    Button("OK") { controller.dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Not Now") { controller.dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Start Recording") {
                        if controller.blocker == .awaitingNames {
                            controller.nameLaterAndRecord()
                        } else {
                            controller.confirm()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(16)
        .frame(width: 360)
        .onHover { controller.isPaused = $0 }
    }

    private var title: String {
        if case .startFailed = controller.blocker { return "\(controller.pending?.displayName ?? "Call") not recorded" }
        return "\(controller.pending?.displayName ?? "Call") detected"
    }

    /// Every version that can record says what it records and where it goes; the
    /// waiting-for-names note is added, never swapped in for that.
    private var message: String {
        let consent = Copy.consent(for: controller.pending ?? .manual, cloud: controller.cloudActive)
        switch controller.blocker {
        case nil: return consent
        case .awaitingNames: return "\(consent) \(CallBlocker.awaitingNames.message)"
        case let blocker?: return blocker.message
        }
    }
}

#if DEBUG
    extension ConfirmationController {
        /// Shows the prompt's content without a panel or countdown, for the screenshot
        /// catalog. Debug builds only.
        func stageForScreenshots(
            source: RecordingSource, countdown: Int, cloudActive: Bool,
            blocker: CallBlocker? = nil
        ) {
            waitsForAnswer = blocker?.isFailure == true
            pending = source
            self.countdown = countdown
            self.cloudActive = cloudActive
            self.blocker = blocker
        }
    }
#endif
