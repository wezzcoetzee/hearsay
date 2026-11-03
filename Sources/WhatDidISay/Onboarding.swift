import SwiftUI
import AppKit
import Combine

@MainActor
final class OnboardingController: ObservableObject {
    private var window: NSWindow?
    private let permissions: PermissionsManager
    private let settings: Settings

    init(permissions: PermissionsManager, settings: Settings) {
        self.permissions = permissions
        self.settings = settings
    }

    private var setupComplete: Bool {
        permissions.allGranted && settings.hasOutputFolder
    }

    func presentIfNeeded() {
        permissions.refresh()
        guard !setupComplete else { return }
        present()
    }

    func present() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingView(permissions: permissions,
                                  settings: settings,
                                  onClose: { [weak self] in self?.close() },
                                  onRelaunch: { OnboardingController.relaunch() })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        window.contentView = NSHostingView(rootView: view)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }

    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, microphone, screenRecording, vault, audio, done
    }

    @ObservedObject var permissions: PermissionsManager
    @ObservedObject var settings: Settings
    var onClose: () -> Void
    var onRelaunch: () -> Void

    @State private var step: Step

    init(permissions: PermissionsManager, settings: Settings, startingAt step: Step = .welcome,
         onClose: @escaping () -> Void, onRelaunch: @escaping () -> Void) {
        self.permissions = permissions
        self.settings = settings
        self.onClose = onClose
        self.onRelaunch = onRelaunch
        _step = State(initialValue: step)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .id(step)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: step)
            Divider()
            footer
        }
        .frame(width: 460, height: 580)
        .onAppear { permissions.refresh() }
        // Grants happen in System Settings; pick them up when the user comes back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(AppInfo.displayName)
                .font(.title2).bold()
            Text("Records your huddles and calls, transcribes them locally, and saves notes to your vault.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .microphone: permissionStep(
            icon: "mic.fill",
            title: "Microphone",
            why: "Captures your side of the conversation so your words appear in the transcript.",
            status: permissions.microphone,
            action: { await permissions.request(.microphone) })
        case .screenRecording: permissionStep(
            icon: "rectangle.inset.filled.and.person.filled",
            title: "Screen Recording",
            why: "macOS routes system audio through the Screen Recording permission. It's how the app captures everyone else on the call. No video is ever recorded.",
            status: permissions.screenRecording,
            note: "After you allow it, the app must be relaunched for macOS to apply the change.",
            action: { await permissions.request(.screenRecording) })
        case .vault: vaultStep
        case .audio: audioStep
        case .done: doneStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Two permissions, one time")
                .font(.headline)
            Text("To record both sides of a call, macOS needs your permission for the microphone and for system audio. We'll walk through each and explain why.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Everything is transcribed on-device. Audio never leaves your Mac. If you turn on cloud summaries, only the finished transcript text is sent to summarize.",
                  systemImage: "lock.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            Spacer()
        }
    }

    private func permissionStep(icon: String, title: String, why: String,
                                status: PermissionsManager.Status, note: String? = nil,
                                action: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 26)).foregroundStyle(.tint).frame(width: 40)
                Text(title).font(.title3).bold()
                Spacer()
                statusPill(status)
            }
            Text(why)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Label(note, systemImage: "arrow.clockwise")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if status != .granted {
                Button {
                    Task { await action() }
                } label: {
                    Text("Grant \(title)").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var vaultStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").font(.system(size: 26)).foregroundStyle(.tint).frame(width: 40)
                Text("Vault").font(.title3).bold()
                Spacer()
                statusPill(settings.hasOutputFolder ? .granted : .denied, granted: "Set", pending: "Not set")
            }
            Text("Each call is saved here as a markdown note, one file per conversation. Point this at your Obsidian vault, or any folder you like.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            folderChoice(settings.outputFolderName, choose: settings.chooseOutputFolder)
        }
    }

    private var audioStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill").font(.system(size: 26)).foregroundStyle(.tint).frame(width: 40)
                Text("Audio").font(.title3).bold()
                Spacer()
                Toggle("", isOn: $settings.keepAudio)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Keep audio recordings")
            }
            Text(settings.keepAudioExplanation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if settings.keepAudio {
                HStack(spacing: 8) {
                    Text("Save to").foregroundStyle(.secondary)
                    Spacer()
                    statusPill(settings.audioFolderPath != nil ? .granted : .denied, granted: "Set", pending: "Not set")
                }
                folderChoice(settings.audioFolderName, choose: settings.chooseAudioFolder)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Filename format", text: $settings.audioFilenameFormat)
                        .textFieldStyle(.roundedBorder)
                    Text("Tokens: {date} {time} {source} {track}")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            if !permissions.allGranted {
                Image(systemName: "arrow.clockwise.circle.fill").font(.system(size: 48)).foregroundStyle(.orange)
                Text("One more step").font(.title3).bold()
                Text("If you allowed Screen Recording, relaunch to apply it. Without it you can still record the room from the menu.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Relaunch Now", action: onRelaunch)
                    .buttonStyle(.borderedProminent).controlSize(.large)
            } else if let name = settings.outputFolderName {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(.green)
                Text("You're all set").font(.title3).bold()
                Text("Notes will be saved to \(name). Click the waveform in the menu bar to start recording, or turn on auto-detect to catch huddles automatically.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Image(systemName: "folder.badge.plus").font(.system(size: 48)).foregroundStyle(.orange)
                Text("Almost there").font(.title3).bold()
                Text("Choose where notes are saved and your first recording will land there automatically.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Choose Vault Folder") { settings.chooseOutputFolder() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// The chosen folder with a way to change it, or one prominent button to pick one.
    @ViewBuilder
    private func folderChoice(_ name: String?, choose: @escaping () -> Void) -> some View {
        if let name {
            HStack {
                Label(name, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Change", action: choose)
            }
        } else {
            Button(action: choose) {
                Text("Choose Folder").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func move(by offset: Int) {
        if let next = Step(rawValue: step.rawValue + offset) { step = next }
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { move(by: -1) }
            }
            Spacer()
            stepDots
            Spacer()
            if step != .done {
                Button(step == .welcome ? "Get Started" : "Continue") { move(by: 1) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == .microphone && permissions.microphone != .granted)
            } else {
                Button("Done", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { dot in
                Circle()
                    .fill(dot == step ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    private func statusPill(_ status: PermissionsManager.Status,
                            granted: String = "Granted",
                            pending: String = "Not granted") -> some View {
        HStack(spacing: 5) {
            Image(systemName: status == .granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(status == .granted ? .green : .secondary)
            Text(status == .granted ? granted : pending)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
