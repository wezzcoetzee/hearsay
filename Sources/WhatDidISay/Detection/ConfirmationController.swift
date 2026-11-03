import SwiftUI
import AppKit
import Combine

@MainActor
final class ConfirmationController: ObservableObject {
    @Published private(set) var pending: RecordingSource?
    @Published private(set) var countdown: Int = 0
    @Published private(set) var cloudActive = false

    var onConfirm: ((RecordingSource) -> Void)?
    var onTurnOffAutoDetect: (() -> Void)?
    var isCloudSummaryActive: (() -> Bool)?

    private var panel: NSPanel?
    private var timerTask: Task<Void, Never>?
    private let startSeconds = 15

    func present(source: RecordingSource) {
        guard pending == nil else { return }
        pending = source
        countdown = startSeconds
        cloudActive = isCloudSummaryActive?() ?? false
        showPanel()
        timerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                self.countdown -= 1
            }
            self.dismiss()
        }
    }

    func confirm() { finish(start: true) }
    func dismiss() { finish(start: false) }

    /// Takes the prompt down when the call it's offering to record has already ended,
    /// so "Start Recording" can't begin capturing a call that's over.
    func withdraw(ifEndedBy bundleID: String?) {
        guard let pending else { return }
        if let bundleID, !pending.bundleIDs.contains(bundleID) { return }
        dismiss()
    }

    func turnOffAutoDetect() {
        onTurnOffAutoDetect?()
        dismiss()
    }

    private func finish(start: Bool) {
        timerTask?.cancel()
        timerTask = nil
        let source = pending
        pending = nil
        panel?.orderOut(nil)
        panel = nil
        if start, let source { onConfirm?(source) }
    }

    private func showPanel() {
        let panel = NSPanel.floating(contentView: NSHostingView(rootView: ConfirmationView(controller: self)),
                                     size: NSSize(width: 360, height: 140),
                                     styleMask: [.titled])
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
                Image(systemName: "record.circle").foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text("\(controller.pending?.displayName ?? "Call") detected")
                    .font(.headline)
                Spacer()
                // Once a second for fifteen seconds, so a rolling digit costs nothing.
                Text("Dismisses in \(controller.countdown)s")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(reduceMotion ? nil : .snappy, value: controller.countdown)
            }
            Text(controller.cloudActive
                 ? "Nothing is recorded unless you choose to. Everyone on the call may be recorded. Audio stays on your Mac; the transcript is sent to Anthropic for the summary."
                 : "Nothing is recorded unless you choose to. Everyone on the call may be recorded, and everything stays on your Mac.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Turn Off Auto-Detect") { controller.turnOffAutoDetect() }
                    .buttonStyle(.link)
                    .controlSize(.small)
                Spacer()
                Button("Not Now") { controller.dismiss() }
                Button("Start Recording") { controller.confirm() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

#if DEBUG
extension ConfirmationController {
    /// Shows the prompt's content without a panel or countdown, for the screenshot
    /// catalog. Debug builds only.
    func stageForScreenshots(source: RecordingSource, countdown: Int, cloudActive: Bool) {
        pending = source
        self.countdown = countdown
        self.cloudActive = cloudActive
    }
}
#endif
