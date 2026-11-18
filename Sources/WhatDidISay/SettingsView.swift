import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var permissions: PermissionsManager
    @ObservedObject var recorder: RecordingController
    @State private var showCloudConsent = false
    /// Not observable, so re-read whenever the user may have changed it.
    @State private var accessibilityTrusted = PermissionsManager.accessibilityTrusted

    var body: some View {
        Form {
            Section("General") {
                Toggle(isOn: $settings.autoDetect) {
                    Text("Auto-detect calls")
                    Text(permissions.screenRecording.isGranted ? Copy.autoDetectExplanation : Copy.autoDetectNeedsScreenRecording)
                }
                .disabled(!permissions.screenRecording.isGranted)
                Toggle(isOn: $settings.showRecordingPanel) {
                    Text("Show recording panel")
                    Text("A small floating timer with a stop button while recording.")
                }
                Toggle(isOn: $settings.launchAtLogin) {
                    Text("Launch at login")
                    if !settings.launchAtLoginRefused {
                        Text("Starts quietly in the menu bar when you log in.")
                    } else {
                        Text("macOS didn't allow it. Move the app to Applications, then try again.")
                    }
                }
            }

            Section {
                permissionRow(
                    "Microphone", detail: "Your side of a call, and the room in person.",
                    allowed: permissions.microphone.isGranted,
                    action: PermissionsManager.actionTitle(for: .microphone, status: permissions.microphone)
                ) {
                    Task { await permissions.request(.microphone) }
                }
                permissionRow(
                    "Screen Recording",
                    detail: permissions.screenRecordingRequested && !permissions.screenRecording.isGranted
                        ? "Everyone else on a call. \(Copy.relaunchHint)" : "Everyone else on a call.",
                    allowed: permissions.screenRecording.isGranted
                ) {
                    Task { await permissions.request(.screenRecording) }
                } extra: {
                    if permissions.screenRecordingRequested {
                        RelaunchButton(isBusy: recorder.isBusy)
                    }
                }
                permissionRow(
                    "Accessibility", detail: "Optional. Detects Google Meet and reads names off the call window.",
                    allowed: accessibilityTrusted
                ) {
                    PermissionsManager.requestAccessibility()
                }
            } header: {
                Text("Permissions")
            }

            Section("Notes") {
                LabeledContent {
                    FolderChoice(path: settings.outputFolderPath, choose: settings.chooseOutputFolder)
                } label: {
                    Text("Notes folder")
                    Text("Each recording becomes a markdown note here.")
                }
                Picker(selection: $settings.model) {
                    ForEach(Settings.availableModels, id: \.self) { model in
                        Text(Self.modelLabel(model)).tag(model)
                    }
                } label: {
                    Text("Transcription accuracy")
                    Text("More accurate takes longer. Everything runs on your Mac.")
                }
                Toggle(isOn: $settings.diarize) {
                    Text("Separate remote speakers")
                    Text("Labels each voice on the call as Speaker 1, Speaker 2, and so on. In-person recordings always do this.")
                }
            }

            Section {
                Toggle(isOn: $settings.keepAudio) {
                    Text("Keep audio after each note is saved")
                    Text(settings.keepAudioExplanation)
                }
                if settings.keepAudio {
                    LabeledContent("Audio folder") {
                        FolderChoice(path: settings.audioFolderPath, choose: settings.chooseAudioFolder)
                    }
                    TextField(text: $settings.audioFilenameFormat, prompt: Text(Settings.defaultAudioFilenameFormat)) {
                        Text("File names")
                        Text("{track} becomes mic or system; the rest come from the recording.")
                    }
                }
            } header: {
                Text("Audio")
            }

            Section {
                Toggle(isOn: $settings.summaryEnabled) {
                    Text("AI summary")
                    Text("Adds a summary and action items to each note, and names it by topic.")
                }
                if settings.summaryEnabled {
                    Picker("Summarize with", selection: $settings.summaryBackend) {
                        ForEach(SummaryBackend.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    switch settings.summaryBackend {
                    case .local:
                        TextField("Ollama model", text: $settings.localSummaryModel)
                    case .cloud:
                        SecureField("Anthropic API key", text: $settings.anthropicAPIKey, prompt: Text("Required"))
                    }
                }
            } header: {
                Text("Summary")
            } footer: {
                if settings.summaryEnabled {
                    Group {
                        switch settings.summaryBackend {
                        case .local:
                            Text("Runs on your Mac through Ollama. Nothing leaves the device.")
                                .foregroundStyle(.secondary)
                        case .cloud where settings.anthropicAPIKey.isEmpty:
                            // A warning keeps primary text, like every Caution.
                            Caution("Add an API key. Until then no summary is made and nothing is sent.")
                        case .cloud:
                            Label(Copy.cloudBoundary, systemImage: "cloud")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
        .navigationTitle("Settings")
        .onAppear(perform: refreshPermissions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
        .onChange(of: settings.summaryBackend) { _, newValue in
            if newValue == .cloud && !settings.hasAcknowledgedCloud {
                showCloudConsent = true
            }
        }
        .alert("Send transcripts to the cloud?", isPresented: $showCloudConsent) {
            Button("Cancel", role: .cancel) { settings.summaryBackend = .local }
            Button("Use Cloud Summaries") { settings.hasAcknowledgedCloud = true }
        } message: {
            Text(
                "With cloud summaries on, the finished transcript text of each call is sent to Anthropic to generate the summary. Your audio never leaves your Mac. Turn this off any time to keep everything on-device."
            )
        }
    }

    private func refreshPermissions() {
        permissions.refresh()
        accessibilityTrusted = PermissionsManager.accessibilityTrusted
    }

    private func permissionRow<Extra: View>(
        _ name: String, detail: String, allowed: Bool, action: String = "Allow…",
        allow: @escaping () -> Void,
        @ViewBuilder extra: () -> Extra = { EmptyView() }
    ) -> some View {
        LabeledContent {
            if allowed {
                PermissionStatus(name: name, allowed: true)
            } else {
                HStack {
                    Button(action, action: allow)
                        .accessibilityLabel("\(action) for \(name)")
                    extra()
                }
            }
        } label: {
            Text(name)
            Text(detail)
        }
    }

    private static func modelLabel(_ model: String) -> String {
        switch model {
        case "tiny": return "Fastest"
        case "base": return "Balanced"
        case "small": return "Accurate"
        case "large-v3": return "Most accurate"
        default: return model
        }
    }
}
