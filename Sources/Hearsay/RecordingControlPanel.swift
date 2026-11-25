import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingControlPanelController: ObservableObject {
    @Published private(set) var isCollapsed = false
    /// When the current recording started; `nil` while nothing is recording.
    @Published private(set) var since: Date?
    /// The recorder's capture warning, shown here because the panel is what the user
    /// is looking at mid-call.
    @Published var warning: CaptureIssue?
    /// What is being recorded, so the panel names it.
    @Published private(set) var source: RecordingSource = .manual

    var onStop: (() -> Void)?

    var isEnabled = true {
        didSet { reconcile() }
    }

    let levels: AudioLevelMonitor

    private var panel: NSPanel?

    init(levels: AudioLevelMonitor) {
        self.levels = levels
    }

    func update(for state: RecordingController.State, source: RecordingSource) {
        if case .recording(let since) = state {
            self.since = since
            self.source = source
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
        panel.title = "Recording panel"
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
    /// nearest the screen's edges stays put, so a panel parked in a corner stays flush.
    func toggleCollapsed() {
        let animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(animates ? .easeInOut(duration: Self.resizeDuration) : nil) {
            isCollapsed.toggle()
        }
        guard let panel else { return }

        let current = panel.frame
        let screen = panel.screen?.visibleFrame ?? current
        let pinsRight = current.midX > screen.midX
        let pinsBottom = current.midY < screen.midY
        let target = NSRect(
            x: pinsRight ? current.maxX - size.width : current.minX,
            y: pinsBottom ? current.minY : current.maxY - size.height,
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

    private var size: NSSize { isCollapsed ? Self.collapsedSize : Self.expandedSize }

    private static let resizeDuration = 0.2
    static let expandedSize = NSSize(width: 292, height: 92)
    static let collapsedSize = NSSize(width: 168, height: 40)
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
            if controller.isCollapsed {
                collapsed.transition(.opacity)
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
                    title
                    timer.font(.title3).monospacedDigit().foregroundStyle(.primary)
                }
                Spacer(minLength: 4)
                IconButton(
                    symbol: "arrow.down.right.and.arrow.up.left",
                    label: "Collapse recording panel", help: "Collapse"
                ) {
                    controller.toggleCollapsed()
                }

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
                    level: levels.mic, isSilent: levels.micSilent)
                if levels.tracksSystemAudio {
                    ChannelMeter(
                        symbol: "speaker.wave.2.fill", name: "Call audio level",
                        level: levels.system, isSilent: false)
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

    /// The source while all is well; the problem, flagged, when something isn't.
    @ViewBuilder
    private var title: some View {
        if let issue {
            Label {
                Text(issue.title).lineLimit(1)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            // The panel's one sign that part of the call is being missed: a size up
            // from the source name it replaces.
            .font(.subheadline.weight(.medium))
            .help("\(issue.title). \(issue.detail)")
            .accessibilityHint(issue.detail)
        } else {
            Text(controller.source.recordingName)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var collapsed: some View {
        Button {
            controller.toggleCollapsed()
        } label: {
            HStack(spacing: 8) {
                RecordingDot()
                timer.font(.callout).monospacedDigit().foregroundStyle(.primary)
                if issue != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    LevelMeter(level: max(levels.mic, levels.system), segments: 5, height: 10)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(
                width: RecordingControlPanelController.collapsedSize.width,
                height: RecordingControlPanelController.collapsedSize.height
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(issue.map { "\($0.title). \($0.detail)" } ?? "Expand recording panel")
        .accessibilityLabel("Expand recording panel")
        .accessibilityValue(issue?.title ?? "")
    }

    /// What's wrong right now: a track that stopped, else a mic that hears nothing.
    /// Shown in both layouts, so collapsing never hides a problem.
    private var issue: CaptureIssue? {
        controller.warning ?? (levels.micSilent ? .micSilent : nil)
    }

    @ViewBuilder
    private var timer: some View {
        if let since = controller.since {
            TimelineView(.periodic(from: since, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(since))
                Text(ElapsedTime.clock(elapsed))
                    .accessibilityLabel("Recording \(controller.source.recordingName), \(ElapsedTime.spoken(elapsed))")
            }
        } else {
            Text("00:00").monospacedDigit()
        }
    }
}

/// The same glyph as the menu's recording row and the menu-bar icon, so "recording"
/// looks one way everywhere. Deliberately still: anything that moves for the whole
/// call repaints the panel the whole call. The ticking timer and the meters already
/// show it's live.
private struct RecordingDot: View {
    var body: some View {
        Image(systemName: "record.circle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .accessibilityHidden(true)
    }
}
