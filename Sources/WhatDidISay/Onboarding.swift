import AppKit
import Combine
import SwiftUI

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

    /// Shows the guide until the user finishes it once. Someone who set everything up
    /// before the guide remembered that counts as finished.
    func presentIfNeeded() {
        permissions.refresh()
        if setupComplete { settings.hasCompletedOnboarding = true }
        guard !settings.hasCompletedOnboarding else { return }
        present()
    }

    func present() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingView(
            permissions: permissions,
            settings: settings,
            startingAt: OnboardingView.Step.resuming(permissions: permissions, settings: settings),
            onClose: { [weak self] in self?.finish() },
            onRelaunch: { OnboardingController.relaunch() })
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: OnboardingView.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up \(AppInfo.displayName)"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // A normal window, so System Settings can come in front of it while the user
        // switches a permission on.
        window.center()
        window.contentView = NSHostingView(rootView: view)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        window?.orderOut(nil)
        window = nil
    }

    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        // Quit only once the new copy is running, so a failed launch never leaves the
        // user with no app at all.
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                NSLog("Relaunch failed: \(error)")
                return
            }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}

/// A setup assistant in the macOS pattern: each step explains one thing, and its
/// action sits in the footer's default slot, turning into Continue once it's done.
struct OnboardingView: View {
    static let size = NSSize(width: 460, height: 400)

    enum Step: Int, CaseIterable {
        case welcome, microphone, screenRecording, notesFolder, done

        /// Where to pick up after a relaunch: the first thing still missing, or the
        /// start for someone who hasn't been asked anything yet.
        @MainActor
        static func resuming(permissions: PermissionsManager, settings: Settings) -> Step {
            if permissions.microphone == .unknown { return .welcome }
            if !permissions.microphone.isGranted { return .microphone }
            if !permissions.screenRecording.isGranted { return .screenRecording }
            if !settings.hasOutputFolder { return .notesFolder }
            return .done
        }
    }

    /// The footer's trailing buttons for a step: an optional quiet one, and the one
    /// prominent button that takes Return.
    private struct Actions {
        var secondary: (title: String, run: () -> Void)?
        var primary: (title: String, run: () -> Void)
    }

    @ObservedObject var permissions: PermissionsManager
    @ObservedObject var settings: Settings
    var onClose: () -> Void
    var onRelaunch: () -> Void

    @State private var step: Step

    init(
        permissions: PermissionsManager, settings: Settings, startingAt step: Step = .welcome,
        onClose: @escaping () -> Void, onRelaunch: @escaping () -> Void
    ) {
        self.permissions = permissions
        self.settings = settings
        self.onClose = onClose
        self.onRelaunch = onRelaunch
        _step = State(initialValue: step)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            content
                .id(step)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 32)
                .padding(.top, 36)
                .padding(.bottom, 20)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: step)
            Divider()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onAppear { permissions.refresh() }
        // Grants happen in System Settings; pick them up when the user comes back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .microphone: microphoneStep
        case .screenRecording: screenRecordingStep
        case .notesFolder: notesFolderStep
        case .done: doneStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(AppInfo.displayName)
                .font(.title2).bold()
            Text(
                "Records your calls and in-person meetings, transcribes them on your Mac, and saves each one as a markdown note."
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            Label(
                "Audio never leaves your Mac. If you turn on cloud summaries, only the finished transcript text is sent to Anthropic.",
                systemImage: "lock.fill"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 6)
            Text("Setup takes a minute: two permissions and a folder.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var microphoneStep: some View {
        stepLayout(icon: "mic.fill", title: "Microphone", allowed: permissions.microphone.isGranted) {
            Text("Records your side of a call, and everyone in the room when you record in person.")
            if permissions.microphone == .denied {
                Caution(
                    "Microphone access is off. Turn on \(AppInfo.displayName) in System Settings, under Privacy & Security, Microphone."
                )
                .foregroundStyle(.primary)
            }
        }
    }

    private var screenRecordingStep: some View {
        stepLayout(
            icon: "rectangle.inset.filled.and.person.filled", title: "Screen Recording",
            allowed: permissions.screenRecording.isGranted
        ) {
            Text(
                "macOS hands out call audio through the Screen Recording permission. It's how the app hears everyone else on a call. No video is ever recorded."
            )
            // Plain secondary text, as in the menu and Settings; Relaunch Now is the
            // footer's default button.
            if permissions.screenRecordingRequested && !permissions.screenRecording.isGranted {
                Text(Copy.relaunchHint)
            } else {
                Text("Only calls need it. You can skip this and still record in person.")
            }
        }
    }

    private var notesFolderStep: some View {
        stepLayout(icon: "folder.fill", title: "Notes Folder") {
            Text(
                "Each recording becomes a markdown note in this folder. Point it at your Obsidian vault, or any folder you like."
            )
            if settings.hasOutputFolder {
                FolderChoice(path: settings.outputFolderPath, choose: settings.chooseOutputFolder, spread: true)
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 14) {
            let callsReady = permissions.allGranted
            Image(systemName: callsReady ? "checkmark.seal.fill" : "person.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(callsReady ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tint))
                .accessibilityHidden(true)
            Text(callsReady ? "You're all set" : "Ready to record in person").font(.title3).bold()
            Text(
                callsReady
                    ? "Each recording becomes a note in \u{201C}\(settings.outputFolderName ?? "your notes folder")\u{201D}. Click the waveform in the menu bar to start recording."
                    : "To record calls too, allow Screen Recording from the menu or Settings, then relaunch."
            )
            .foregroundStyle(.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            // Detection only offers calls, so it's offered once calls can be recorded.
            if callsReady {
                VStack(alignment: .leading, spacing: 6) {
                    TrailingSwitch(title: "Auto-detect calls", isOn: $settings.autoDetect)
                    Text(Copy.autoDetectExplanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Icon, title and, for a permission, whether it's allowed on one line; then the
    /// explanation.
    private func stepLayout<Body: View>(
        icon: String, title: String, allowed: Bool? = nil,
        @ViewBuilder body: () -> Body
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title).foregroundStyle(.tint).frame(width: 40)
                    .accessibilityHidden(true)
                Text(title).font(.title3).bold()
                Spacer()
                if let allowed {
                    PermissionStatus(
                        name: title, allowed: allowed,
                        pendingRelaunch: title == "Screen Recording" && permissions.screenRecordingRequested
                    )
                    .font(.callout)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                body()
            }
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func next() {
        if let following = Step(rawValue: step.rawValue + 1) { step = following }
    }

    private var actions: Actions {
        switch step {
        case .welcome:
            return Actions(primary: ("Get Started", next))
        case .microphone:
            if permissions.microphone.isGranted { return Actions(primary: ("Continue", next)) }
            let title = permissions.microphone == .denied ? "Open System Settings" : "Allow Microphone…"
            return Actions(primary: (title, { Task { await permissions.request(.microphone) } }))
        case .screenRecording:
            if permissions.screenRecording.isGranted { return Actions(primary: ("Continue", next)) }
            if permissions.screenRecordingRequested {
                return Actions(secondary: ("Later", next), primary: ("Relaunch Now", onRelaunch))
            }
            return Actions(
                secondary: ("Skip", next),
                primary: (
                    "Allow Screen Recording…",
                    {
                        Task { await permissions.request(.screenRecording) }
                    }
                ))
        case .notesFolder:
            return settings.hasOutputFolder
                ? Actions(primary: ("Continue", next))
                : Actions(primary: ("Choose Notes Folder…", settings.chooseOutputFolder))
        case .done:
            return Actions(primary: ("Done", onClose))
        }
    }

    private var footer: some View {
        let actions = actions
        return HStack {
            if step != .welcome {
                Button("Back") { if let previous = Step(rawValue: step.rawValue - 1) { step = previous } }
            }
            Spacer()
            if let secondary = actions.secondary {
                Button(secondary.title, action: secondary.run)
            }
            Button(actions.primary.title, action: actions.primary.run)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        // Centred on the footer, not between buttons whose widths change per step, so
        // the progress dots never move.
        .overlay { stepDots }
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
}
