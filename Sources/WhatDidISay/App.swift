import AppKit
import SwiftUI

enum AppInfo {
    static let displayName = "What Did I Say"
}

/// The tinted waveform tile and app name that head the menu and Settings.
struct AppHeader<Trailing: View>: View {
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(
                    Color.accentColor.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .accessibilityHidden(true)
            Text(AppInfo.displayName).font(.headline)
            Spacer()
            trailing
        }
    }
}

extension NotePipeline.Stage {
    var title: String {
        switch self {
        case .transcribing: "Transcribing"
        case .identifyingSpeakers: "Identifying speakers"
        case .summarizing: "Summarizing"
        case .reviewing: "Confirming participants"
        case .saving: "Saving note"
        }
    }
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

    #if DEBUG
        init() {
            if let directory = ScreenshotRenderer.outputDirectory {
                ScreenshotRenderer.run(into: directory)
            }
        }
    #endif

    var body: some Scene {
        MenuBarExtra {
            MenuContent(
                recorder: coordinator.recorder,
                settings: coordinator.settings,
                permissions: coordinator.permissions,
                history: coordinator.recorder.history,
                levels: coordinator.recorder.levels,
                onboarding: coordinator.onboarding)
        } label: {
            Image(nsImage: MenuBarIcon.image(recording: coordinator.recorder.isRecording))
                .accessibilityLabel(
                    coordinator.recorder.isRecording
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
    /// Not observed here: only `RecordingStatus` redraws with the meters.
    let levels: AudioLevelMonitor
    let onboarding: OnboardingController

    @State private var showConsentAlert = false
    @State private var pendingSource: RecordingSource = .manual
    @State private var confirmingQuit = false
    @State private var discarding: RecordingSession?

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
                RecordingStatus(since: since, levels: levels, warning: recorder.captureWarning)
            }

            Divider()

            recordButton
            statusRow
            needsAttentionBlock
            historyBlock

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { permissions.refresh() }
        .alert("Start recording?", isPresented: $showConsentAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Record") {
                settings.hasAcknowledgedConsent = true
                Task { await recorder.toggle(source: pendingSource) }
            }
        } message: {
            Text(
                pendingSource.usesSystemAudio
                    ? "Everyone on the call may be recorded. Audio and transcripts stay on your Mac unless you turn on cloud summaries. Record responsibly."
                    : "Everyone in the room may be recorded. Audio and transcripts stay on your Mac unless you turn on cloud summaries. Record responsibly."
            )
        }
        .alert("Quit before this call is a note?", isPresented: $confirmingQuit) {
            Button("Cancel", role: .cancel) {}
            Button("Quit", role: .destructive) {
                Task {
                    await recorder.finishForQuit()
                    NSApplication.shared.terminate(nil)
                }
            }
        } message: {
            Text("Its audio is kept and shows under Needs attention when you reopen the app.")
        }
        .confirmationDialog(
            "Discard this recording?",
            isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } }),
            presenting: discarding
        ) { session in
            Button("Discard Recording", role: .destructive) { Task { await recorder.discard(session) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The audio is deleted and no note is saved. This can't be undone.")
        }
    }

    private var header: some View {
        AppHeader {
            StatusBadge(state: recorder.state)
            Button {
                if recorder.isBusy {
                    confirmingQuit = true
                } else {
                    NSApplication.shared.terminate(nil)
                }
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

    /// Stopping is a single action; starting is a split button, so the common case
    /// (a call) stays one click and recording the room is one menu away.
    @ViewBuilder
    private var recordButton: some View {
        if recorder.isRecording {
            Button {
                Task { await recorder.toggle() }
            } label: {
                recordLabel
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)
            .disabled(recordButtonDisabled)
        } else {
            Menu {
                Button("Record a Call") { begin(.manual) }
                Button("Record the Room") { begin(.inPerson) }
            } label: {
                recordLabel
            } primaryAction: {
                begin(.manual)
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.accentColor)
            .disabled(recordButtonDisabled)
        }
    }

    private var recordLabel: some View {
        Label(buttonTitle, systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle")
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
    }

    private func begin(_ source: RecordingSource) {
        pendingSource = source
        if settings.hasAcknowledgedConsent {
            Task { await recorder.toggle(source: source) }
        } else {
            showConsentAlert = true
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if case .finishing = recorder.state {
            progressRow("Saving audio", cancellable: false)
        }
        if case .processing(let stage) = recorder.state {
            progressRow(stage.title, cancellable: true, audioSaved: true)
        }
        if case .failed(let message) = recorder.state {
            failureRow(message)
        }
        if let save = recorder.lastSave {
            savedRow(save)
        }
    }

    private func progressRow(_ text: String, cancellable: Bool, audioSaved: Bool = false) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("\(text)…").font(.caption).foregroundStyle(.secondary)
            if audioSaved {
                Label("Audio saved", systemImage: "checkmark")
                    .font(.caption2).foregroundStyle(.secondary)
            }
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
                if !settings.hasOutputFolder {
                    Button("Choose Folder") { settings.chooseOutputFolder() }
                        .controlSize(.small)
                }
                // A failed note is retried from Needs attention; a failed start tries
                // the same kind of recording again.
                if recorder.failedToStart {
                    Button("Try Again") { begin(recorder.lastSource) }
                        .controlSize(.small)
                    if !permissions.isGranted(for: recorder.lastSource) {
                        Button("Open Setup Guide") { onboarding.present() }
                            .controlSize(.small)
                    }
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
        VStack(alignment: .leading, spacing: 4) {
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
            if let warning = save.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Recordings that never became notes. Audio is kept until the user processes or
    /// discards each one, so a crash mid-transcription costs a retry, not the call.
    @ViewBuilder
    private var needsAttentionBlock: some View {
        let pending = recorder.needsAttention
        if !pending.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Needs Attention · \(pending.count)")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    Spacer()
                    if pending.count > 1 {
                        Button("Process All") { Task { await recorder.processAll() } }
                            .font(.caption2)
                            .buttonStyle(.borderless)
                            .disabled(recorder.isBusy || !settings.hasOutputFolder)
                    }
                }
                .padding(.horizontal, 2)
                ForEach(pending.prefix(Self.visiblePending), id: \.id) { session in
                    PendingRow(
                        session: session,
                        canProcess: !recorder.isBusy && settings.hasOutputFolder,
                        onProcess: { Task { await recorder.retry(session) } },
                        onDiscard: { discarding = session })
                }
                if pending.count > Self.visiblePending {
                    Text("and \(pending.count - Self.visiblePending) more")
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }
            }
        }
    }

    private static let visiblePending = 5

    @ViewBuilder
    private var historyBlock: some View {
        if !history.entries.isEmpty {
            Divider()
            historySection
        } else if permissions.allGranted && settings.hasOutputFolder && recorder.needsAttention.isEmpty {
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
    private func permissionRow(_ name: String, status: PermissionsManager.Status, pane: PermissionsManager.Pane)
        -> some View
    {
        HStack(spacing: 6) {
            Image(systemName: status.isGranted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(status.isGranted ? .green : .secondary)
                .accessibilityLabel(status.isGranted ? "granted" : "not granted")
            Text(name).font(.caption)
            Spacer()
            if !status.isGranted {
                Button(status == .unknown ? "Allow" : "Open Settings") {
                    Task { await permissions.request(pane) }
                }
                .controlSize(.small)
            }
        }
    }

    private var recordButtonDisabled: Bool {
        switch recorder.state {
        case .finishing, .processing: return true
        case .recording: return false
        // Recording the room only needs the microphone, so Screen Recording can't
        // disable the button. Starting a call without it fails with a clear message.
        case .idle, .failed: return !permissions.microphone.isGranted
        }
    }

    private var buttonTitle: String {
        switch recorder.state {
        case .recording: return "Stop Recording"
        case .finishing: return "Saving…"
        case .processing(let stage): return "\(stage.title)…"
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
                HistoryRow(
                    entry: entry,
                    onOpen: { NSWorkspace.shared.open($0) },
                    onRemove: { history.remove(entry) })
            }
        }
    }
}

/// The live part of the menu while recording: timer, meters, and the mic warning.
/// Kept in its own view so the meters' fifteen updates a second redraw only this.
private struct RecordingStatus: View {
    let since: Date
    @ObservedObject var levels: AudioLevelMonitor
    let warning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TimelineView(.periodic(from: since, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(since))
                Label("Recording  \(ElapsedTime.clock(elapsed))", systemImage: "record.circle.fill")
                    .font(.callout.weight(.medium)).foregroundStyle(.red).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Recording, \(ElapsedTime.spoken(elapsed))")
            }
            meterRow("Microphone", symbol: "mic.fill", level: levels.mic, isSilent: levels.micSilent)
            if levels.tracksSystemAudio {
                meterRow("Call audio", symbol: "speaker.wave.2.fill", level: levels.system, isSilent: false)
            }
            if let warning {
                caution(warning)
            } else if levels.micSilent {
                caution(
                    "Nothing is reaching the microphone. Check it isn't muted and that the right input device is selected."
                )
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            .red.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func caution(_ text: String) -> some View {
        Text(text)
            .font(.caption2).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func meterRow(_ name: String, symbol: String, level: Float, isSilent: Bool) -> some View {
        HStack(spacing: 8) {
            ChannelMeter(
                symbol: symbol, name: "\(name) level",
                level: level, isSilent: isSilent, segments: 14)
            Text(isSilent ? "no sound" : name)
                .font(.caption2)
                .foregroundStyle(isSilent ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
            Spacer(minLength: 0)
        }
    }
}

private struct PendingRow: View {
    let session: RecordingSession
    let canProcess: Bool
    let onProcess: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        ListRow(
            title: session.source.displayName,
            subtitle:
                "\(session.startedAt.formatted(.dateTime.month().day().hour().minute())) · \(ElapsedTime.clock(Int(session.duration))) · \(status)"
        ) { hovering in
            RowIconButton(
                symbol: "arrow.clockwise", help: "Make a note from this recording",
                label: "Make a note from this recording, \(session.source.displayName)",
                hovering: hovering, action: onProcess
            )
            .disabled(!canProcess)
            RowIconButton(
                symbol: "trash", help: "Discard recording",
                label: "Discard recording, \(session.source.displayName)",
                hovering: hovering, action: onDiscard)
        }
    }

    private var status: String {
        session.progress == .transcribed ? "transcript saved" : "audio only"
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let onOpen: (URL) -> Void
    let onRemove: () -> Void

    var body: some View {
        ListRow(
            title: entry.source,
            subtitle: entry.date.formatted(.dateTime.month().day().hour().minute())
        ) { hovering in
            // Notes can be moved or deleted in the vault; don't offer to open a ghost.
            if let note = entry.noteURL, FileManager.default.fileExists(atPath: note.path) {
                RowIconButton(
                    symbol: "doc.text", help: "Open note",
                    label: "Open note for \(entry.source)",
                    hovering: hovering
                ) { onOpen(note) }
            }
            RowIconButton(
                symbol: "xmark.circle", help: "Remove from list",
                label: "Remove \(entry.source) from list",
                hovering: hovering, action: onRemove)
        }
    }
}

/// A two-line menu row whose trailing buttons brighten while the pointer is over it.
private struct ListRow<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let actions: (_ hovering: Bool) -> Actions

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.medium))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            actions(hovering)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(
            hovering ? Color.primary.opacity(0.07) : .clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .onHover { hovering = $0 }
    }
}

private struct RowIconButton: View {
    let symbol: String
    let help: String
    let label: String
    let hovering: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(label)
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
