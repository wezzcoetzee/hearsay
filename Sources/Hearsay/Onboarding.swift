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
        // `open Hearsay.app --args -showSetupGuide YES` shows it again for one launch.
        let forced = UserDefaults.standard.bool(forKey: "showSetupGuide")
        if setupComplete && !forced { settings.hasCompletedOnboarding = true }
        guard forced || !settings.hasCompletedOnboarding else { return }
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
        let window = SetupWindow(
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

    /// Closes the guide and opens the menu once, so someone who has never seen the app
    /// learns where it lives: it has no Dock icon, and a full menu bar can hide it.
    private func finish() {
        settings.hasCompletedOnboarding = true
        window?.orderOut(nil)
        window = nil
        DispatchQueue.main.async { Self.openMenu() }
    }

    /// SwiftUI's `MenuBarExtra` has no way to open itself, so this clicks its status
    /// item. If a macOS update moves the button, nothing happens and the guide just
    /// closes, as it did before.
    private static func openMenu() {
        func statusButton(in view: NSView) -> NSStatusBarButton? {
            if let button = view as? NSStatusBarButton { return button }
            return view.subviews.lazy.compactMap(statusButton(in:)).first
        }
        let button = NSApp.windows.lazy
            .compactMap { $0.contentView.flatMap(statusButton(in:)) }
            .first
        button?.performClick(nil)
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

/// Esc closes the guide, as its close button does. Setup isn't marked finished, and the
/// menu still offers whatever step is missing.
private final class SetupWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

/// A setup assistant in the macOS pattern: each step explains one thing, and its
/// action sits in the footer's default slot, turning into Continue once it's done.
struct OnboardingView: View {
    /// The window's size for every step whose content fits; Done, with its choices,
    /// grows taller.
    static let size = NSSize(width: 460, height: 320)

    enum Step: Int, CaseIterable {
        case welcome, microphone, screenRecording, notesFolder, done

        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .microphone: "Microphone"
            case .screenRecording: "Screen Recording"
            case .notesFolder: "Notes Folder"
            case .done: "Done"
            }
        }

        /// What VoiceOver hears for the progress dots, and when the step changes.
        var position: String { "Step \(rawValue + 1) of \(Self.allCases.count), \(title)" }

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
    /// Not published by macOS, so it's re-read whenever the app becomes active again.
    @State private var accessibilityTrusted: Bool

    init(
        permissions: PermissionsManager, settings: Settings, startingAt step: Step = .welcome,
        accessibilityTrusted: Bool = PermissionsManager.accessibilityTrusted,
        onClose: @escaping () -> Void, onRelaunch: @escaping () -> Void
    ) {
        self.permissions = permissions
        self.settings = settings
        self.onClose = onClose
        self.onRelaunch = onRelaunch
        _step = State(initialValue: step)
        _accessibilityTrusted = State(initialValue: accessibilityTrusted)
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
                .padding(.bottom, 12)
            // Above the divider, not over the footer, whose buttons can reach the middle.
            stepDots
                .padding(.bottom, 16)
            Divider()
            footer
        }
        .frame(width: Self.size.width)
        .frame(minHeight: Self.size.height)
        // Taller than the minimum only when a step's content needs it; the window
        // follows, since the hosting view sizes it.
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { permissions.refresh() }
        // Grants happen in System Settings; pick them up when the user comes back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
            accessibilityTrusted = PermissionsManager.accessibilityTrusted
        }
        .onChange(of: step) { _, step in Announcer.post(step.position) }
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
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(AppInfo.displayName)
                .font(.title2).bold()
            Text("Records your calls and in-person meetings, transcribes them on your Mac, and saves each one as a markdown note.")
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
        }
        .frame(maxWidth: .infinity)
    }

    private var microphoneStep: some View {
        stepLayout(
            icon: "mic.fill", title: "Microphone",
            allowed: permissions.microphone == .unknown ? nil : permissions.microphone.isGranted
        ) {
            Text("Records your side of a call, and everyone in the room when you record in person.")
            if permissions.microphone == .denied {
                Caution("Microphone access is off. Turn on \(AppInfo.displayName) in System Settings, under Privacy & Security, Microphone.")
                    .foregroundStyle(.primary)
            }
        }
    }

    private var screenRecordingStep: some View {
        // macOS reports "not allowed" for both never-asked and refused, so status waits
        // until it's allowed or the user has asked.
        let granted = permissions.screenRecording.isGranted
        return stepLayout(
            icon: "rectangle.inset.filled.and.person.filled", title: "Screen Recording",
            allowed: granted || permissions.screenRecordingRequested ? granted : nil
        ) {
            Text("Lets the app hear everyone else on a call. macOS calls this Screen Recording. No video is ever recorded.")
            // macOS can't say whether the prompt was accepted until a relaunch, so this
            // says what has to be true first, and the footer can reopen System Settings.
            if permissions.screenRecordingRequested && !granted {
                Text("Once it's switched on for \(AppInfo.displayName) in System Settings, relaunch to apply it.")
            } else {
                Text("Only calls need it. You can skip this and still record in person.")
            }
        }
    }

    private var notesFolderStep: some View {
        stepLayout(icon: "folder.fill", title: "Notes Folder") {
            Text("Each recording becomes a markdown note in this folder. Point it at your Obsidian vault, or any folder you like.")
            if settings.hasOutputFolder {
                FolderChoice(path: settings.outputFolderPath, choose: settings.chooseOutputFolder, spread: true)
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 10) {
            let callsReady = permissions.allGranted
            Image(systemName: callsReady ? "checkmark.seal.fill" : "person.2.fill")
                .font(.system(size: 36))
                .foregroundStyle(callsReady ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tint))
                .accessibilityHidden(true)
            Text(callsReady ? "You're all set" : "Ready to record in person").font(.title3).bold()
            let menuBar = Text("The app lives in the menu bar as \(Image(systemName: "waveform")). Done opens it so you can see where.")
            Group {
                if callsReady {
                    Text("Each recording becomes a note in \u{201C}\(settings.outputFolderName ?? "your notes folder")\u{201D}. ") + menuBar
                } else {
                    menuBar + Text(" To record calls too, go back to Screen Recording.")
                }
            }
            .foregroundStyle(.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            // Detection only offers calls, so it's offered once calls can be recorded.
            if callsReady {
                Text("One choice left:")
                VStack(alignment: .leading, spacing: 6) {
                    TrailingSwitch(title: "Auto-detect calls", isOn: $settings.autoDetect)
                    Text(Copy.autoDetectExplanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // Meet is found through a browser tab's title, which needs Accessibility.
                    if settings.autoDetect && !accessibilityTrusted {
                        Divider().padding(.vertical, 2)
                        HStack {
                            Text("Google Meet also needs Accessibility.")
                                .font(.callout)
                            Spacer()
                            Button("Allow…") { PermissionsManager.requestAccessibility() }
                                .controlSize(.small)
                        }
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
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
        if let following = Step(rawValue: step.rawValue + 1) { go(to: following) }
    }

    /// One transaction for the crossfade and any change in window height, so the two
    /// move together.
    private func go(to destination: Step) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { step = destination }
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
                return Actions(
                    secondary: ("Open Settings", { permissions.openSettings(.screenRecording) }),
                    primary: ("Relaunch Now", onRelaunch))
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
            if step == .welcome {
                // Welcome has no Back, so its slot sets expectations instead.
                Text("Setup takes a minute: two permissions and a folder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Button("Back") { if let previous = Step(rawValue: step.rawValue - 1) { go(to: previous) } }
                    .keyboardShortcut("[", modifiers: .command)
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
        .accessibilityLabel(step.position)
    }
}
