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
        let view = ConfirmationView(controller: self)
        let hosting = NSHostingView(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 140),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: frame.maxX - size.width - 24,
                y: frame.maxY - size.height - 24
            ))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

struct ConfirmationView: View {
    @ObservedObject var controller: ConfirmationController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "record.circle").foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text("\(controller.pending?.displayName ?? "Call") detected")
                    .font(.headline)
                Spacer()
                Text("Dismisses in \(controller.countdown)s")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
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
