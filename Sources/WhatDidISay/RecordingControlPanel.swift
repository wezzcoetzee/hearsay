import SwiftUI
import AppKit
import Combine

@MainActor
final class RecordingControlPanelController: ObservableObject {
    @Published var isMinimized = false
    @Published private(set) var since: Date?

    var onStop: (() -> Void)?

    var isEnabled = true {
        didSet { reconcile() }
    }

    let levels: AudioLevelMonitor

    private var recordingSince: Date?
    private var panel: NSPanel?

    init(levels: AudioLevelMonitor) {
        self.levels = levels
    }

    func update(for state: RecordingController.State) {
        if case .recording(let since) = state {
            recordingSince = since
        } else {
            recordingSince = nil
        }
        reconcile()
    }

    private func reconcile() {
        if let recordingSince, isEnabled {
            show(since: recordingSince)
        } else {
            hide()
        }
    }

    private func show(since: Date) {
        self.since = since
        if let panel {
            resize(panel)
            panel.orderFrontRegardless()
            return
        }

        let view = RecordingControlPanelView(controller: self)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.expandedSize.width, height: Self.expandedSize.height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: view)

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

    private func hide() {
        since = nil
        panel?.orderOut(nil)
        panel = nil
    }

    func toggleMinimized() {
        isMinimized.toggle()
        if let panel { resize(panel) }
    }

    private func resize(_ panel: NSPanel) {
        let target = isMinimized ? Self.minimizedSize : Self.expandedSize
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        var frame = panel.frame
        frame.size = target
        frame.origin = NSPoint(x: topLeft.x, y: topLeft.y - target.height)
        panel.setFrame(frame, display: true, animate: true)
    }

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

    var body: some View {
        Group {
            if controller.isMinimized {
                minimized
            } else {
                expanded
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RecordingDot(level: levels.mic)
                VStack(alignment: .leading, spacing: 1) {
                    Text(levels.micSilent ? "No mic input" : "Recording")
                        .font(.caption)
                        .foregroundStyle(levels.micSilent ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
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
                ChannelMeter(symbol: "mic.fill", name: "Microphone level",
                             level: levels.mic, isSilent: levels.micSilent)
                    .help(levels.micSilent ? "No sound from your microphone" : "Microphone level")
                ChannelMeter(symbol: "speaker.wave.2.fill", name: "Call audio level",
                             level: levels.system, isSilent: false)
                    .help("Call audio level")
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: RecordingControlPanelController.expandedSize.width,
               height: RecordingControlPanelController.expandedSize.height)
    }

    private var minimized: some View {
        Button {
            controller.toggleMinimized()
        } label: {
            HStack(spacing: 8) {
                RecordingDot(level: levels.mic)
                timer.font(.callout).monospacedDigit().foregroundStyle(.primary)
                LevelMeter(level: max(levels.mic, levels.system), segments: 5, height: 10)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(width: RecordingControlPanelController.minimizedSize.width,
                   height: RecordingControlPanelController.minimizedSize.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Expand recording controls")
        .accessibilityLabel("Expand recording controls")
    }

    @ViewBuilder
    private var timer: some View {
        if let since = controller.since {
            TimelineView(.periodic(from: since, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(since))
                Text(String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
                    .accessibilityLabel("Recording, \(elapsed / 60) minutes \(elapsed % 60) seconds")
            }
        } else {
            Text("00:00").monospacedDigit()
        }
    }
}

private struct RecordingDot: View {
    let level: Float

    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)
            .scaleEffect(1 + CGFloat(level) * 0.4)
            .animation(.linear(duration: 0.08), value: level)
            .opacity(pulsing ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
            .accessibilityHidden(true)
    }
}
