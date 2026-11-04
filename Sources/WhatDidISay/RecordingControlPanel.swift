import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingControlPanelController: ObservableObject {
    @Published private(set) var isMinimized = false
    /// When the current recording started; `nil` while nothing is recording.
    @Published private(set) var since: Date?
    /// The recorder's capture warning, shown here because the panel is what the user
    /// is looking at mid-call.
    @Published var warning: String?

    var onStop: (() -> Void)?

    var isEnabled = true {
        didSet { reconcile() }
    }

    let levels: AudioLevelMonitor

    private var panel: NSPanel?

    init(levels: AudioLevelMonitor) {
        self.levels = levels
    }

    func update(for state: RecordingController.State) {
        if case .recording(let since) = state {
            self.since = since
        } else {
            since = nil
        }
        reconcile()
    }

    private func reconcile() {
        if since != nil, isEnabled {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let hosting = NSHostingView(rootView: RecordingControlPanelView(controller: self))
        // The panel owns its size so it can animate between the two layouts.
        hosting.sizingOptions = []
        let panel = NSPanel.floating(contentView: hosting, size: size, styleMask: [.borderless])
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Cross-fades the layouts while the window resizes on the same curve. The corner
    /// nearest the screen edge stays put, so a panel parked top-right stays flush.
    func toggleMinimized() {
        let animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(animates ? .easeInOut(duration: Self.resizeDuration) : nil) {
            isMinimized.toggle()
        }
        guard let panel else { return }

        let current = panel.frame
        let screen = panel.screen?.visibleFrame ?? current
        let pinsRight = current.midX > screen.midX
        let target = NSRect(
            x: pinsRight ? current.maxX - size.width : current.minX,
            y: current.maxY - size.height,
            width: size.width, height: size.height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animates ? Self.resizeDuration : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            // The shadow follows the content's shape, which only settles at the end.
            MainActor.assumeIsolated { self?.panel?.invalidateShadow() }
        }
    }

    private var size: NSSize { isMinimized ? Self.minimizedSize : Self.expandedSize }

    private static let resizeDuration = 0.2
    static let expandedSize = NSSize(width: 252, height: 92)
    static let minimizedSize = NSSize(width: 160, height: 40)
}

struct RecordingControlPanelView: View {
    @ObservedObject var controller: RecordingControlPanelController
    @ObservedObject var levels: AudioLevelMonitor

    init(controller: RecordingControlPanelController) {
        self.controller = controller
        self.levels = controller.levels
    }

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        // Fills the window rather than sizing to the content, so the material and
        // border resize with the panel and the two layouts can overlap mid-fade.
        ZStack(alignment: .topLeading) {
            if controller.isMinimized {
                minimized.transition(.opacity)
            } else {
                expanded.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(.white.opacity(0.08)))
        .clipShape(shape)
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RecordingDot()
                VStack(alignment: .leading, spacing: 1) {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(isHealthy ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                        .help(controller.warning ?? "")
                    timer.font(.title3).monospacedDigit().foregroundStyle(.primary)
                }
                Spacer(minLength: 4)
                Button {
                    controller.toggleMinimized()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .help("Minimize")
                .accessibilityLabel("Minimize control panel")

                Button {
                    controller.onStop?()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .help("Stop recording")
                .accessibilityLabel("Stop recording")
            }

            HStack(spacing: 14) {
                ChannelMeter(
                    symbol: "mic.fill", name: "Microphone level",
                    level: levels.mic, isSilent: levels.micSilent
                )
                .help(levels.micSilent ? "No sound from your microphone" : "Microphone level")
                if levels.tracksSystemAudio {
                    ChannelMeter(
                        symbol: "speaker.wave.2.fill", name: "Call audio level",
                        level: levels.system, isSilent: false
                    )
                    .help("Call audio level")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(
            width: RecordingControlPanelController.expandedSize.width,
            height: RecordingControlPanelController.expandedSize.height)
    }

    private var minimized: some View {
        Button {
            controller.toggleMinimized()
        } label: {
            HStack(spacing: 8) {
                RecordingDot()
                timer.font(.callout).monospacedDigit().foregroundStyle(.primary)
                LevelMeter(level: max(levels.mic, levels.system), segments: 5, height: 10)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(
                width: RecordingControlPanelController.minimizedSize.width,
                height: RecordingControlPanelController.minimizedSize.height
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Expand recording controls")
        .accessibilityLabel("Expand recording controls")
    }

    private var isHealthy: Bool { controller.warning == nil && !levels.micSilent }

    private var status: String {
        if controller.warning != nil { return "Audio interrupted" }
        return levels.micSilent ? "No mic input" : "Recording"
    }

    @ViewBuilder
    private var timer: some View {
        if let since = controller.since {
            TimelineView(.periodic(from: since, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(since))
                Text(ElapsedTime.clock(elapsed))
                    .accessibilityLabel("Recording, \(ElapsedTime.spoken(elapsed))")
            }
        } else {
            Text("00:00").monospacedDigit()
        }
    }
}

/// Deliberately still: anything that moves for the whole call repaints the panel the
/// whole call. The ticking timer and the meters already show it's live.
private struct RecordingDot: View {
    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}
