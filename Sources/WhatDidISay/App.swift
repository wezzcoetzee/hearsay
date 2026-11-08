import AppKit
import SwiftUI

enum AppInfo {
    static let displayName = "What Did I Say"
}

/// The tinted waveform tile and app name that head the menu.
struct AppHeader<Trailing: View>: View {
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.callout.weight(.semibold))
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

/// The menu-bar icon is the only status visible without opening the menu, so it
/// carries the states worth noticing: recording, recording with a capture problem
/// (the one failure that costs the call), and something waiting on you (a failure,
/// Needs Attention, or the participant review).
enum MenuBarIcon {
    enum Status: Equatable { case idle, recording, recordingWithIssue(CaptureIssue), attention }

    @MainActor
    static func status(of recorder: RecordingController) -> Status {
        switch recorder.state {
        case .recording:
            if let issue = recorder.captureWarning ?? (recorder.levels.micSilent ? .micSilent : nil) {
                return .recordingWithIssue(issue)
            }
            return .recording
        case .failed, .processing(.reviewing): return .attention
        default: return recorder.needsAttention.isEmpty ? .idle : .attention
        }
    }

    static func image(_ status: Status) -> NSImage {
        switch status {
        case .idle, .attention:
            let name = status == .idle ? "waveform" : "waveform.badge.exclamationmark"
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
            image.isTemplate = true
            return image
        case .recording:
            return symbol("record.circle.fill", color: .systemRed)
        case .recordingWithIssue:
            // The red record symbol with an orange warning badge in its corner, so it
            // still reads as recording.
            let record = symbol("record.circle.fill", color: .systemRed)
            let badge = symbol("exclamationmark.triangle.fill", color: .systemOrange, pointSize: 8)
            let image = NSImage(
                size: NSSize(width: record.size.width + 3, height: record.size.height),
                flipped: false
            ) { rect in
                record.draw(in: NSRect(origin: .zero, size: record.size))
                badge.draw(
                    in: NSRect(
                        x: rect.maxX - badge.size.width, y: 0,
                        width: badge.size.width, height: badge.size.height))
                return true
            }
            image.isTemplate = false
            return image
        }
    }

    private static func symbol(_ name: String, color: NSColor, pointSize: CGFloat? = nil) -> NSImage {
        var configuration = NSImage.SymbolConfiguration(paletteColors: [color])
        if let pointSize {
            configuration = configuration.applying(.init(pointSize: pointSize, weight: .bold))
        }
        let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        let colored = base.withSymbolConfiguration(configuration) ?? base
        colored.isTemplate = false
        return colored
    }

    static func accessibilityLabel(_ status: Status) -> String {
        switch status {
        case .idle: AppInfo.displayName
        case .recording: "\(AppInfo.displayName), recording"
        case .recordingWithIssue(let issue): "\(AppInfo.displayName), recording, \(issue.title)"
        case .attention: "\(AppInfo.displayName), needs attention"
        }
    }
}

@main
struct WhatDidISayApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(
                recorder: coordinator.recorder,
                settings: coordinator.settings,
                permissions: coordinator.permissions,
                history: coordinator.recorder.history,
                levels: coordinator.recorder.levels,
                onShowReview: { coordinator.participantReview.bringToFront() })
        } label: {
            let status = MenuBarIcon.status(of: coordinator.recorder)
            Image(nsImage: MenuBarIcon.image(status))
                .accessibilityLabel(MenuBarIcon.accessibilityLabel(status))
        }
        .menuBarExtraStyle(.window)

        SwiftUI.Settings {
            SettingsView(
                settings: coordinator.settings, permissions: coordinator.permissions,
                recorder: coordinator.recorder)
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
    var onShowReview: () -> Void = {}

    @State private var showConsentAlert = false
    @State private var pendingSource: RecordingSource = .manual
    @State private var confirmingQuit = false
    @State private var confirmingClear = false
    @State private var deleting: RecordingSession?
    @State private var showingAllPending = false

    static let width: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            // Setup that's still missing comes first, and its button is the prominent
            // one: a disabled Start would only draw the eye to something that can't work.
            if !permissions.microphone.isGranted {
                Divider()
                permissionsBanner
            } else if !settings.hasOutputFolder {
                Divider()
                folderBanner
            }

            if startDisabledReason == nil || !recorder.state.isIdle {
                Divider()
                currentJob
            }
            if permissions.microphone.isGranted, !permissions.screenRecording.isGranted, recorder.state.isIdle {
                callsNeedScreenRecording
            }
            statusRow
            needsAttentionBlock
            historyBlock

            Divider()
            footer
        }
        .padding(14)
        .frame(width: Self.width)
        // Back to the short list once it's short again, so Show Fewer never goes
        // missing while a scroller is still up.
        .onChange(of: recorder.needsAttention.count) { _, count in
            if count <= Self.visiblePending { showingAllPending = false }
        }
        .onAppear {
            permissions.refresh()
            // A vault moved or an external volume unplugged shows now, before a call is
            // recorded with nowhere to go.
            settings.revalidateFolders()
            recorder.saveConfirmationSeen()
        }
        .alert("Start recording?", isPresented: $showConsentAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Start Recording") {
                settings.hasAcknowledgedConsent = true
                Task { await record(pendingSource) }
            }
        } message: {
            Text(Copy.consent(for: pendingSource, cloud: settings.cloudSummaryActive))
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
            Text("Its audio is kept and shows under Needs Attention when you reopen the app.")
        }
        .confirmationDialog(
            "Delete the \(deleting.map(PendingRow.name) ?? "recording")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { session in
            Button("Delete Recording", role: .destructive) { Task { await recorder.discard(session) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(Copy.deleteRecordingConsequence)
        }
        .confirmationDialog("Clear the recent recordings list?", isPresented: $confirmingClear) {
            Button("Clear List", role: .destructive) { history.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the list is cleared. Your notes stay in \(settings.outputFolderName ?? "your notes folder").")
        }
    }

    private var header: some View {
        AppHeader {
            IconButton(symbol: "power", label: "Quit \(AppInfo.displayName)", help: "Quit") {
                if recorder.isBusy {
                    confirmingQuit = true
                } else {
                    NSApplication.shared.terminate(nil)
                }
            }
            .keyboardShortcut("q")
        }
    }

    /// One slot always holds what the app is doing: the live recording with its Stop
    /// button, the note being made from it, or the way to start the next one.
    @ViewBuilder
    private var currentJob: some View {
        switch recorder.state {
        case .recording(let since):
            RecordingStatus(
                since: since, source: recorder.lastSource,
                folderPath: settings.outputFolderPath,
                levels: levels, issue: recorder.captureWarning)
            Button {
                Task { await recorder.toggle() }
            } label: {
                recordLabel("Stop Recording", symbol: "stop.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)
        case .finishing:
            ProcessingCard(title: "Saving audio", source: recorder.processingSource)
        case .processing(.reviewing):
            // Waiting on the user, not working: no spinner. Recording stays one click
            // away, as it is on the call prompt; starting parks this review under Needs
            // Attention to name later.
            ProcessingCard(
                title: "Who was talking?", source: recorder.processingSource,
                waitingOnUser: true, onReview: onShowReview)
            startControls
        case .processing(let stage):
            // Cancelling once the note is being written could leave it written and
            // queued for a retry, so the last stage runs to the end.
            ProcessingCard(
                title: stage.title, source: recorder.processingSource,
                onCancel: stage == .saving ? nil : { recorder.cancelProcessing() })
        case .idle, .failed:
            startControls
        }
    }

    /// Starting is one click: Record a Call leads, Record in Person sits beside it.
    /// Without Screen Recording a call can't be captured, so the only button records in
    /// person instead of offering something that would fail.
    private var startControls: some View {
        HStack(spacing: 6) {
            if permissions.screenRecording.isGranted {
                Button {
                    begin(.manual)
                } label: {
                    recordLabel("Record a Call", symbol: "record.circle")
                }
                // Both kinds of recording in plain sight: a stranger in a meeting room
                // shouldn't have to find the second one inside a menu.
                Button {
                    begin(.inPerson)
                } label: {
                    Text("In Person")
                        .font(.body.weight(.semibold))
                        .padding(.vertical, 3)
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .help("Record a meeting in the room: the microphone only, every voice told apart")
                .accessibilityLabel("Record in Person")
            } else {
                // Without Screen Recording only the room can be recorded, so that's
                // the one button; the line below says how to add calls.
                Button {
                    begin(.inPerson)
                } label: {
                    recordLabel("Record in Person", symbol: "record.circle")
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(startDisabledReason != nil)
        .help(startDisabledReason ?? "")
    }

    private func recordLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).leadButtonLabel()
    }

    /// Why Start can't be pressed right now, or `nil` when it can.
    private var startDisabledReason: String? {
        if !permissions.microphone.isGranted { return "Allow Microphone access to record." }
        if !settings.hasOutputFolder { return "Choose a notes folder to record." }
        return nil
    }

    private func begin(_ source: RecordingSource) {
        pendingSource = source
        if settings.hasAcknowledgedConsent {
            Task { await record(source) }
        } else {
            showConsentAlert = true
        }
    }

    /// Starts recording; a review still waiting for names is parked to name later.
    private func record(_ source: RecordingSource) async {
        if case .processing(.reviewing) = recorder.state {
            await recorder.nameLaterAndRecord(source)
        } else {
            await recorder.toggle(source: source)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if case .failed(let message) = recorder.state {
            failureRow(message)
        }
        if let save = recorder.lastSave {
            savedRow(save)
        }
    }

    private func failureRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Caution(message, tint: .red).font(.subheadline)
            Spacer(minLength: 0)
            IconButton(symbol: "xmark", label: "Dismiss message", help: "Dismiss") { recorder.dismissFailure() }
        }
    }

    private var folderBanner: some View {
        setupStep(
            "Choose where notes are saved", symbol: "folder",
            detail: "Pick a folder or Obsidian vault. Each recording becomes a markdown note there.",
            action: "Choose Notes Folder…", perform: settings.chooseOutputFolder)
    }

    /// A setup step the menu can't record without: what's missing, why, and the one
    /// prominent button that fixes it. The microphone and the notes folder look alike.
    private func setupStep(
        _ title: String, symbol: String, detail: String,
        action: String, perform: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Caution(title, symbol: symbol, tint: .accentColor)
            Text(detail)
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: perform) {
                Text(action).leadButtonLabel()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func savedRow(_ save: RecordingController.SaveConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Note saved to \(save.folderName)")
                    .lineLimit(1).truncationMode(.middle)
                    .help(settings.outputFolderPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "")
                Spacer()
                if let url = save.noteURL {
                    Button("Open") { NSWorkspace.shared.open(url) }
                        .controlSize(.small)
                }
                if save.warning != nil {
                    IconButton(symbol: "xmark", label: "Dismiss message", help: "Dismiss") { recorder.dismissSave() }
                }
            }
            if let warning = save.warning {
                Caution(warning).font(.subheadline)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Recordings that never became notes. Audio is kept until the user processes or
    /// deletes each one, so a crash mid-transcription costs a retry, not the call.
    @ViewBuilder
    private var needsAttentionBlock: some View {
        let pending = recorder.needsAttention
        if !pending.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label {
                        Text("Needs Attention · \(pending.count)")
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    }
                    .font(.subheadline.weight(.semibold))
                    Spacer()
                    if pending.count > 1 {
                        Button("Make All Notes") { Task { await recorder.processAll() } }
                            .controlSize(.small)
                            .disabled(processBlockedReason != nil)
                            .help(processBlockedReason ?? "Make notes from every recording, one at a time.")
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
                if showingAllPending {
                    // Every row reachable, so each can be made into a note or deleted on
                    // its own; scrolled so the menu still fits the screen.
                    ScrollView { pendingRows(pending) }
                        .frame(height: min(CGFloat(pending.count) * 46, 276))
                } else {
                    pendingRows(pending.prefix(Self.visiblePending))
                }
                if pending.count > Self.visiblePending {
                    Button(showingAllPending ? "Show Fewer" : "Show All \(pending.count)") {
                        showingAllPending.toggle()
                    }
                    .buttonStyle(.link)
                    .font(.subheadline)
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    private func pendingRows(_ sessions: some Sequence<RecordingSession>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(sessions), id: \.id) { session in
                PendingRow(
                    session: session,
                    blockedReason: processBlockedReason,
                    onProcess: { Task { await recorder.retry(session) } },
                    onDelete: { deleting = session })
            }
        }
    }

    /// Why a recording can't be made into a note right now, or `nil` when it can.
    private var processBlockedReason: String? {
        if recorder.isBusy { return "Available once the current recording is done." }
        if !settings.hasOutputFolder { return "Choose a notes folder first." }
        return nil
    }

    /// Kept short so the menu fits a laptop screen with every block showing.
    private static let visiblePending = 3
    private var visibleHistory: Int { recorder.needsAttention.isEmpty ? 5 : 3 }

    @ViewBuilder
    private var historyBlock: some View {
        if !history.entries.isEmpty {
            Divider()
            historySection
        } else if permissions.allGranted && settings.hasOutputFolder && recorder.needsAttention.isEmpty
            && recorder.state.isIdle && recorder.lastSave == nil
        {
            Divider()
            VStack(spacing: 5) {
                Image(systemName: "waveform.and.mic")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text("Recordings will appear here.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if settings.cloudSummaryActive {
                Label(Copy.cloudBoundary, systemImage: "cloud")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Detection only offers calls it can record, so without Screen Recording the
            // switch would do nothing; the "Calls need Screen Recording" line covers it.
            if permissions.screenRecording.isGranted {
                TrailingSwitch(title: "Auto-detect calls", isOn: $settings.autoDetect)
                    .controlSize(.small)
                    .help(Copy.autoDetectExplanation)
            }
            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .keyboardShortcut(",")
        }
    }

    /// Nothing can be recorded without the microphone, so this is the first step and
    /// its button is the prominent one.
    private var permissionsBanner: some View {
        setupStep(
            "Allow the microphone to start recording", symbol: "mic",
            detail: "It records your side of a call, and everyone in the room in person.",
            action: permissions.microphone == .denied ? "Open System Settings" : "Allow Microphone…"
        ) {
            Task { await permissions.request(.microphone) }
        }
    }

    /// Recording in person works without Screen Recording, so a missing grant is a
    /// quiet note, not a warning. Relaunch is offered once it's been asked for.
    private var callsNeedScreenRecording: some View {
        HStack(spacing: 6) {
            Text(permissions.screenRecordingRequested ? Copy.relaunchHint : "Calls need Screen Recording.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if permissions.screenRecordingRequested {
                RelaunchButton(isBusy: recorder.isBusy)
            } else {
                Button("Allow…") { Task { await permissions.request(.screenRecording) } }
                    .accessibilityLabel("Allow Screen Recording")
            }
        }
        .controlSize(.small)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("Recent Recordings")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let folder = settings.outputFolderPath {
                    IconButton(symbol: "folder", label: "Open the notes folder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: folder))
                    }
                }
                Button("Clear…") { confirmingClear = true }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .help("Clear this list. Notes are not deleted.")
            }
            .padding(.horizontal, 2)
            ForEach(history.entries.prefix(visibleHistory)) { entry in
                HistoryRow(entry: entry, onRemove: { history.remove(entry) })
            }
        }
    }
}

/// The note being made from a recording, in the slot the recording occupied.
private struct ProcessingCard: View {
    let title: String
    let source: RecordingSource
    var waitingOnUser = false
    var onReview: (() -> Void)?
    var onCancel: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            if waitingOnUser {
                Image(systemName: "person.2.fill").foregroundStyle(.tint)
                    .accessibilityHidden(true)
            } else {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Working")
            }
            VStack(alignment: .leading, spacing: 1) {
                // An ellipsis says "in progress", which waiting on the user isn't.
                Text(waitingOnUser ? title : "\(title)…").lineLimit(1)
                Text(source.recordingName)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .help("Stop making this note. The recording moves to Needs Attention.")
            }
            // Plain, not prominent: Record a Call below stays the one lead action.
            if let onReview {
                Button("Review…", action: onReview)
                    .help("Show the window asking who was talking")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(
            waitingOnUser
                ? "The note is saved once you've named the speakers." : "You can record again once this note is saved.")
    }
}

/// The live part of the menu while recording: what's recorded, where it goes, the
/// timer and meters. Kept in its own view so the meters' fifteen updates a second
/// redraw only this.
private struct RecordingStatus: View {
    let since: Date
    let source: RecordingSource
    let folderPath: String?
    @ObservedObject var levels: AudioLevelMonitor
    let issue: CaptureIssue?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TimelineView(.periodic(from: since, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(since))
                HStack(spacing: 6) {
                    // The glyph carries the red; the words stay primary for contrast.
                    Image(systemName: "record.circle.fill").foregroundStyle(.red)
                    Text("Recording")
                    Text(source.recordingName).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(ElapsedTime.clock(elapsed)).monospacedDigit()
                }
                .font(.body.weight(.medium))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Recording \(source.recordingName), \(ElapsedTime.spoken(elapsed))")
            }
            meterRow("Microphone", symbol: "mic.fill", level: levels.mic, isSilent: levels.micSilent)
            if levels.tracksSystemAudio {
                meterRow("Call audio", symbol: "speaker.wave.2.fill", level: levels.system, isSilent: false)
            }
            if let shown = issue ?? (levels.micSilent ? .micSilent : nil) {
                Caution("\(shown.title). \(shown.detail)").font(.subheadline)
            }
            if let folderPath {
                Label("Saves to \((folderPath as NSString).lastPathComponent)", systemImage: "folder")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .help((folderPath as NSString).abbreviatingWithTildeInPath)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            .quaternary.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func meterRow(_ name: String, symbol: String, level: Float, isSilent: Bool) -> some View {
        HStack(spacing: 8) {
            ChannelMeter(
                symbol: symbol, name: "\(name) level",
                level: level, isSilent: isSilent, segments: 14)
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
    }
}

private struct PendingRow: View {
    let session: RecordingSession
    let blockedReason: String?
    let onProcess: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            // What's missing leads, since that's what the row asks you to act on.
            RowText(
                title: session.source.recordingName,
                subtitle: "\(status) · \(Self.when(session))", subtitleLines: 1
            )
            .help("\(status) · \(Self.when(session)) · \(ElapsedTime.length(session.duration))")
            Spacer()
            // The way to recover, so it's drawn at full strength; delete stays quiet.
            IconButton(
                symbol: waitingForNames ? "person.2" : "arrow.clockwise",
                label: "\(waitingForNames ? "Name the speakers" : "Make a note"), \(Self.name(session))",
                help: blockedReason
                    ?? (waitingForNames ? "Name the speakers and save the note" : "Make a note from this recording"),
                emphasized: true, action: onProcess
            )
            .disabled(blockedReason != nil)
            IconButton(
                symbol: "trash", label: "Delete \(Self.name(session))",
                help: "Delete recording", emphasized: hovering, action: onDelete)
        }
        .rowChrome(hovering: hovering)
        .onHover { hovering = $0 }
    }

    /// Which recording, in words that tell rows of the same app apart: for VoiceOver
    /// labels and the delete confirmation.
    static func name(_ session: RecordingSession) -> String {
        "\(session.source.recordingName) from \(when(session))"
    }

    static func when(_ session: RecordingSession) -> String {
        session.startedAt.formatted(.dateTime.month().day().hour().minute())
    }

    private var waitingForNames: Bool { session.setAsideReason == RecordingController.waitingForNames }

    /// What's still missing, not how far it got.
    private var status: String {
        session.setAsideReason
            ?? (session.progress == .transcribed ? "transcribed, note not saved" : "not transcribed yet")
    }
}

/// A recent note. The whole row opens it; removing it from the list is a hover (or
/// context-menu) action, since it's rare and never deletes the note itself.
private struct HistoryRow: View {
    let entry: HistoryEntry
    let onRemove: () -> Void

    @State private var hovering = false

    /// Notes can be moved or deleted in the vault; don't offer to open a ghost.
    private var note: URL? {
        entry.noteURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if let note { NSWorkspace.shared.open(note) }
            } label: {
                RowText(title: entry.source, subtitle: subtitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(note == nil)
            .help(note == nil ? "The note was moved or deleted" : "Open note")
            .accessibilityLabel("\(entry.source), \(subtitle)")
            .accessibilityHint(note == nil ? "" : "Opens the note")
            .accessibilityAction(named: "Remove from list", onRemove)

            IconButton(
                symbol: "minus.circle", label: "Remove \(entry.source) from list",
                help: "Remove from list (the note is kept)", action: onRemove
            )
            .opacity(hovering ? 1 : 0)
            // Hidden controls mustn't take keyboard focus; the context menu and the
            // accessibility action cover keyboard and VoiceOver.
            .disabled(!hovering)
            .accessibilityHidden(true)
        }
        .rowChrome(hovering: hovering)
        .onHover { hovering = $0 }
        .contextMenu {
            if let note {
                Button("Open Note") { NSWorkspace.shared.open(note) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([note]) }
                Divider()
            }
            Button("Remove from List", action: onRemove)
        }
    }

    /// Who was there first, since that's what tells one Slack Huddle from the next,
    /// capped at two names so a big meeting can't push the date off the row. A missing
    /// note leads, since it explains why the row won't open.
    private var subtitle: String {
        let date = entry.date.formatted(.dateTime.month().day().hour().minute())
        let parts = [note == nil ? "note not found" : nil, people, date, entry.duration.map(ElapsedTime.length)]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private var people: String? {
        guard let names = entry.participants, !names.isEmpty else { return nil }
        let shown = names.prefix(2).joined(separator: ", ")
        return names.count > 2 ? "\(shown) +\(names.count - 2)" : shown
    }
}

private struct RowText: View {
    let title: String
    let subtitle: String
    var subtitleLines = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(subtitleLines)
        }
    }
}

private extension View {
    /// The lead button's label in the menu's main slot (Record a Call, Stop Recording,
    /// or a setup step), so the slot keeps its size and weight as setup finishes.
    func leadButtonLabel() -> some View {
        font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
    }

    /// The menu row's padding and its hover highlight.
    func rowChrome(hovering: Bool) -> some View {
        padding(.horizontal, 8).padding(.vertical, 4)
            .background(
                hovering ? Color.primary.opacity(0.07) : .clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
