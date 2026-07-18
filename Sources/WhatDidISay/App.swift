import SwiftUI
import AppKit

enum AppInfo {
    static let displayName = "What Did I Say"
}

enum MenuBarIcon {
    static func image(recording: Bool) -> NSImage {
        let symbolName = recording ? "record.circle.fill" : "waveform"
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!

        guard recording else {
            base.isTemplate = true
            return base
        }

        let configuration = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
        let colored = base.withSymbolConfiguration(configuration) ?? base
        colored.isTemplate = false
        return colored
    }
}

@main
struct WhatDidISayApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(recorder: coordinator.recorder,
                        settings: coordinator.settings,
                        permissions: coordinator.permissions,
                        history: coordinator.recorder.history,
                        onboarding: coordinator.onboarding)
        } label: {
            Image(nsImage: MenuBarIcon.image(recording: coordinator.recorder.isRecording))
                .accessibilityLabel(coordinator.recorder.isRecording
                                    ? "\(AppInfo.displayName), recording"
                                    : "\(AppInfo.displayName), idle")
        }
        .menuBarExtraStyle(.window)

        SwiftUI.Settings {
            SettingsView(settings: coordinator.settings)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var recorder: RecordingController
    @ObservedObject var settings: Settings
    @ObservedObject var permissions: PermissionsManager
    @ObservedObject var history: RecordingHistory
    let onboarding: OnboardingController

    @State private var showConsentAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !permissions.allGranted {
                Divider()
                permissionsBanner
            } else if !settings.hasOutputFolder {
                Divider()
                folderBanner
            }

            if case .recording(let since) = recorder.state {
                recordingTimer(since: since)
            }

            Divider()

            recordButton
            statusRow
            historyBlock

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { permissions.refresh() }
        .alert("Start recording this call?", isPresented: $showConsentAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Record") {
                settings.hasAcknowledgedConsent = true
                Task { await recorder.toggle() }
            }
        } message: {
            Text("Everyone on the call may be recorded. Audio and transcripts stay on your Mac unless you turn on cloud summaries. Record responsibly.")
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
            StatusBadge(state: recorder.state)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Quit")
            .accessibilityLabel("Quit \(AppInfo.displayName)")
            .keyboardShortcut("q")
        }
    }

    private func recordingTimer(since: Date) -> some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(since))
            Label(String(format: "Recording  %02d:%02d", elapsed / 60, elapsed % 60),
                  systemImage: "record.circle.fill")
                .font(.callout.weight(.medium)).foregroundStyle(.red).monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.red.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Recording, \(elapsed / 60) minutes \(elapsed % 60) seconds")
        }
    }

    private var recordButton: some View {
        Button {
            if recorder.isRecording || settings.hasAcknowledgedConsent {
                Task { await recorder.toggle() }
            } else {
                showConsentAlert = true
            }
        } label: {
            Label(buttonTitle, systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(recorder.isRecording ? .red : .accentColor)
        .disabled(recordButtonDisabled)
    }

    @ViewBuilder
    private var statusRow: some View {
        if case .finishing = recorder.state {
            progressRow("Saving audio", cancellable: false)
        }
        if case .processing(let stage) = recorder.state {
            progressRow(stage.rawValue, cancellable: true)
        }
        if case .failed(let message) = recorder.state {
            failureRow(message)
        }
        if let save = recorder.lastSave {
            savedRow(save)
        }
    }

    private func progressRow(_ text: String, cancellable: Bool) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("\(text)…").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if cancellable {
                Button("Cancel") { recorder.cancelProcessing() }
                    .controlSize(.small)
            }
        }
    }

    private func failureRow(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Try Again") { Task { await recorder.toggle() } }
                    .controlSize(.small)
                if !permissions.allGranted {
                    Button("Open Setup Guide") { onboarding.present() }
                        .controlSize(.small)
                } else if !settings.hasOutputFolder {
                    Button("Choose Folder") { settings.chooseOutputFolder() }
                        .controlSize(.small)
                }
            }
        }
    }

    private var folderBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Choose where notes are saved", systemImage: "folder.badge.plus")
                .font(.caption).foregroundStyle(.orange)
            Text("Pick a folder or Obsidian vault so recorded calls have somewhere to land.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                settings.chooseOutputFolder()
            } label: {
                Label("Choose Notes Folder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func savedRow(_ save: RecordingController.SaveConfirmation) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Saved to \(save.folderName)")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            if let url = save.noteURL {
                Button("Open") { NSWorkspace.shared.open(url) }
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var historyBlock: some View {
        if !history.entries.isEmpty {
            Divider()
            historySection
        } else if permissions.allGranted && settings.hasOutputFolder {
            Divider()
            VStack(spacing: 5) {
                Image(systemName: "waveform.and.mic")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text("Recorded calls will appear here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if settings.summaryEnabled && settings.summaryBackend == .cloud {
                Label("Cloud summary on: transcripts are sent to Anthropic", systemImage: "cloud")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle(isOn: $settings.autoDetect) {
                Text("Auto-detect huddles & calls").font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var permissionsBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Permissions needed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
            permissionRow("Microphone", status: permissions.microphone, pane: .microphone)
            permissionRow("Screen Recording", status: permissions.screenRecording, pane: .screenRecording)
            Button {
                onboarding.present()
            } label: {
                Label("Open Setup Guide", systemImage: "checklist")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func permissionRow(_ name: String, status: PermissionsManager.Status, pane: PermissionsManager.Pane) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status.isGranted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(status.isGranted ? .green : .secondary)
                .accessibilityLabel(status.isGranted ? "granted" : "not granted")
            Text(name).font(.caption)
            Spacer()
            if !status.isGranted {
                Button("Open Settings") { permissions.openSettings(pane) }
                    .font(.caption2)
            }
        }
    }

    private var recordButtonDisabled: Bool {
        switch recorder.state {
        case .finishing, .processing: return true
        case .recording: return false
        case .idle, .failed: return !permissions.allGranted
        }
    }

    private var buttonTitle: String {
        switch recorder.state {
        case .recording: return "Stop Recording"
        case .finishing: return "Saving…"
        case .processing(let stage): return "\(stage.rawValue)…"
        default: return "Start Recording"
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recent Recordings")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Clear All") { history.clear() }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove all recordings from this list")
            }
            .padding(.horizontal, 2)
            ForEach(history.entries.prefix(5)) { entry in
                HistoryRow(entry: entry,
                           onOpen: { NSWorkspace.shared.open($0) },
                           onRemove: { history.remove(entry) })
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let onOpen: (URL) -> Void
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.source).font(.caption.weight(.medium))
                Text(entry.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let note = entry.noteURL {
                Button {
                    onOpen(note)
                } label: {
                    Image(systemName: "doc.text")
                        .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.borderless)
                .help("Open note")
                .accessibilityLabel("Open note for \(entry.source)")
            }
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.borderless)
            .help("Remove from list")
            .accessibilityLabel("Remove \(entry.source) from list")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(hovering ? Color.primary.opacity(0.07) : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering = $0 }
    }
}

struct StatusBadge: View {
    let state: RecordingController.State

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(text).font(.caption.weight(.medium)).foregroundStyle(color)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(text)")
    }

    private var color: Color {
        switch state {
        case .idle: return .secondary
        case .recording: return .red
        case .finishing, .processing: return .orange
        case .failed: return .red
        }
    }

    private var text: String {
        switch state {
        case .idle: return "Idle"
        case .recording: return "Recording"
        case .finishing: return "Saving"
        case .processing: return "Working"
        case .failed: return "Error"
        }
    }
}
