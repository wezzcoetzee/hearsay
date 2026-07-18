import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @State private var showCloudConsent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                section("General") {
                    Toggle(isOn: $settings.launchAtLogin) {
                        Text("Launch at login")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    helper("Start \(AppInfo.displayName) automatically when you log in to your Mac.")
                }

                section("Transcription") {
                    LabeledContent("Accuracy") {
                        Picker("Accuracy", selection: $settings.model) {
                            ForEach(Settings.availableModels, id: \.self) { model in
                                Text(Self.modelLabel(model)).tag(model)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Toggle(isOn: $settings.diarize) {
                        Text("Separate remote speakers")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    helper("Analyzes the other participants’ voices on-device to label who said what.")
                }

                section("Notes") {
                    LabeledContent("Vault") {
                        Button(settings.outputFolderName ?? "Choose…") {
                            settings.chooseOutputFolder()
                        }
                        .controlSize(.small)
                    }
                    helper("Each call is saved as a markdown note here. Recordings and audio are stored on your Mac and never uploaded.")
                }

                section("Audio") {
                    Toggle(isOn: $settings.keepAudio) {
                        Text("Keep audio recordings")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    if settings.keepAudio {
                        LabeledContent("Save to") {
                            Button(settings.audioFolderName ?? "Choose…") {
                                settings.chooseAudioFolder()
                            }
                            .controlSize(.small)
                        }
                    }
                    helper(settings.keepAudio
                           ? "After a call is transcribed, its audio files are saved to this folder. Without a folder, audio is still deleted."
                           : "Audio is deleted once the note is saved. Turn this on to keep the recordings.")
                }

                section("Summary") {
                    Toggle(isOn: $settings.summaryEnabled) {
                        Text("AI summary")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    if settings.summaryEnabled {
                        Picker("Summarize with", selection: $settings.summaryBackend) {
                            ForEach(SummaryBackend.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        switch settings.summaryBackend {
                        case .local:
                            TextField("Ollama model", text: $settings.localSummaryModel)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                            helper("Runs on your Mac through Ollama. Nothing leaves the device.")
                        case .cloud:
                            SecureField("Anthropic API key", text: $settings.anthropicAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                            Label("Cloud summaries send the finished transcript text, not audio, to Anthropic. Everything else stays on your Mac.",
                                  systemImage: "exclamationmark.bubble")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 360, height: 480)
        .navigationTitle("Settings")
        .onChange(of: settings.keepAudio) { _, isOn in
            if isOn && settings.audioFolderPath == nil {
                settings.chooseAudioFolder()
            }
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
            Text("With cloud summaries on, the finished transcript text of each call is sent to Anthropic to generate the summary. Your audio never leaves your Mac. Turn this off any time to keep everything on-device.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            Text(AppInfo.displayName).font(.headline)
            Spacer()
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Divider()
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func helper(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func modelLabel(_ model: String) -> String {
        switch model {
        case "tiny": return "Fastest"
        case "base": return "Balanced"
        case "small": return "More accurate"
        case "large-v3": return "Most accurate"
        default: return model
        }
    }
}
