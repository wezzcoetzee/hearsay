import SwiftUI
import AppKit
import Combine

@MainActor
final class RecordingControlPanelController: ObservableObject {
    @Published var isMinimized = false
    @Published private(set) var since: Date?

    var onStop: (() -> Void)?

    private var panel: NSPanel?

    func update(for state: RecordingController.State) {
        if case .recording(let since) = state {
            show(since: since)
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
            contentRect: NSRect(x: 0, y: 0, width: expandedSize.width, height: expandedSize.height),
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
        let target = isMinimized ? minimizedSize : expandedSize
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        var frame = panel.frame
        frame.size = target
        frame.origin = NSPoint(x: topLeft.x, y: topLeft.y - target.height)
        panel.setFrame(frame, display: true, animate: true)
    }

    private let expandedSize = NSSize(width: 240, height: 64)
    private let minimizedSize = NSSize(width: 132, height: 40)
}

struct RecordingControlPanelView: View {
    @ObservedObject var controller: RecordingControlPanelController

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
        HStack(spacing: 10) {
            RecordingDot()
            VStack(alignment: .leading, spacing: 1) {
                Text("Recording").font(.caption).foregroundStyle(.secondary)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 240, height: 64)
    }

    private var minimized: some View {
        Button {
            controller.toggleMinimized()
        } label: {
            HStack(spacing: 8) {
                RecordingDot()
                timer.font(.callout).monospacedDigit().foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(width: 132, height: 40)
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
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)
            .opacity(pulsing ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
            .accessibilityHidden(true)
    }
}
