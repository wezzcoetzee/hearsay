import AppKit
import Combine
import Foundation

@MainActor
final class RecordingController: ObservableObject {
    enum State: Equatable {
        case idle
        case recording(since: Date)
        case finishing
        case processing(NotePipeline.Stage)
        case failed(String)

        /// Nothing in progress: a new recording could start.
        var isIdle: Bool {
            switch self {
            case .idle, .failed: true
            case .recording, .finishing, .processing: false
            }
        }
    }

    struct SaveConfirmation: Equatable {
        let noteURL: URL?
        let folderName: String
        /// Something the user asked for that didn't happen, e.g. keeping the audio.
        let warning: String?
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastSave: SaveConfirmation?
    /// Recordings on disk that never became a note: failed, cancelled, or cut short by
    /// a crash or quit. Rebuilt from disk at launch, newest first. The call being
    /// processed right now isn't in it.
    @Published private(set) var needsAttention: [RecordingSession] = []
    private var inFlight: RecordingSession?
    /// Set while "Make All Notes" works through `needsAttention`; cancelling clears it.
    private var processingAll = false
    /// What the latest start attempt recorded, so retrying a failed start repeats it.
    @Published private(set) var lastSource: RecordingSource = .manual
    /// True when the latest failure was a start, so the menu offers to retry the start
    /// rather than point at a recording.
    @Published private(set) var failedToStart = false
    /// Set when a track stops writing mid-call (device unplugged, permission revoked),
    /// so the user knows the rest of the call is missing rather than finding out later.
    @Published private(set) var captureWarning: CaptureIssue?
    private var saveClearTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    /// A cancelled run still unwinding (Whisper only notices cancellation between
    /// tracks). Awaited before the same files are processed or deleted again.
    private var unwinding: Task<Void, Never>?
    /// Covers the awaits inside `start`, where `state` is still idle and a second
    /// start (a double click, or auto-detect firing) would race for the same devices.
    private var isStarting = false

    let settings: Settings
    let permissions: PermissionsManager
    let history: RecordingHistory
    let levels = AudioLevelMonitor()
    private let recordingsFolder: URL

    private let systemCapture: SystemAudioCapture
    private let micCapture: MicCapture
    private let transcriber = TranscriptionService()
    private let diarizer = Diarizer()
    private let activityMonitor = CallActivityMonitor()
    private let participantDetector = ParticipantDetector()
    private let browserDetector = BrowserCallDetector()
    private var current: RecordingSession?
    private var currentTarget: String?
    private var participantAccumulator = ParticipantAccumulator()
    private var detectionTask: Task<Void, Never>?

    /// Set by AppCoordinator to present the review dialog and return the confirmed roster,
    /// or `nil` when the user chooses to delete the call.
    var confirmRoster: ((RosterReview) async -> ReviewedRoster?)?

    init(
        settings: Settings, permissions: PermissionsManager,
        history: RecordingHistory = RecordingHistory(),
        recordingsFolder: URL = RecordingSession.recordingsFolder
    ) {
        self.settings = settings
        self.permissions = permissions
        self.history = history
        self.recordingsFolder = recordingsFolder
        self.systemCapture = SystemAudioCapture(levels: levels.sink)
        self.micCapture = MicCapture(levels: levels.sink)
        micCapture.onInterrupted = reportInterruption(.micStopped)
        systemCapture.onInterrupted = reportInterruption(.callAudioStopped)
        activityMonitor.onEnded = { [weak self] in
            Task { await self?.stop() }
        }
        needsAttention = RecordingSession.unfinished(
            in: recordingsFolder,
            notedPaths: Set(history.entries.compactMap(\.recordingPath)))
    }

    private func bundleID(for source: RecordingSource) async -> String? {
        if source == .googleMeet, let host = await browserDetector.meetBrowserBundleID() {
            return host
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        return source.bundleIDs.first(where: running.contains) ?? source.bundleIDs.first
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var isBusy: Bool {
        switch state {
        case .recording, .finishing, .processing: return true
        case .idle, .failed: return isStarting
        }
    }

    /// What the note being made right now was recorded from: a retried recording's
    /// own source, else the call that just stopped.
    var processingSource: RecordingSource { inFlight?.source ?? lastSource }

    var isProcessing: Bool {
        if case .processing = state { return true }
        return false
    }

    func toggle(source: RecordingSource = .manual) async {
        if isRecording {
            await stop()
        } else {
            await start(source: source)
        }
    }

    func start(source: RecordingSource) async {
        guard !isBusy else { return }
        isStarting = true
        defer { isStarting = false }
        lastSource = source
        // Every early return below is a failed start; cleared once capture is running.
        failedToStart = true

        saveClearTask?.cancel()
        saveClearTask = nil
        lastSave = nil
        permissions.refresh()
        guard permissions.isGranted(for: source) else {
            // Name only what's missing: a mic grant applies at once, Screen Recording
            // only after a relaunch.
            state = .failed(
                permissions.microphone.isGranted
                    ? "Recording a call needs Screen Recording. Allow it in System Settings, then relaunch."
                    : "Allow Microphone access, then try again.")
            return
        }
        guard settings.hasOutputFolder else {
            state = .failed("Choose a notes folder before recording, so this call has somewhere to save.")
            return
        }

        let session = RecordingSession(source: source, in: recordingsFolder)
        let target = await bundleID(for: source)
        do {
            try session.advance(to: .recording)
            if let systemAudioURL = session.systemAudioURL {
                try await systemCapture.start(writingTo: systemAudioURL, targetBundleID: target)
            }
            try micCapture.start(writingTo: session.micAudioURL)
            failedToStart = false
            captureWarning = nil
            current = session
            currentTarget = target
            participantAccumulator = ParticipantAccumulator()
            levels.start(systemAudio: source.usesSystemAudio)
            state = .recording(since: session.startedAt)
            if let target {
                activityMonitor.start(bundleID: target)
                startParticipantDetection(target: target)
            }
        } catch {
            await teardown()
            session.deleteRecording()
            NSLog("Recording start failed: \(error)")
            state = .failed("Couldn't start recording. Another app may be using the microphone or system audio.")
            Announcer.post("Couldn't start recording. Another app may be using the microphone or system audio.")
        }
    }

    /// The Needs Attention reason for a recording whose speakers will be named later.
    static let waitingForNames = "waiting for names"

    /// Stops processing but keeps the audio, so the call lands in Needs Attention. The
    /// user asked for this, so it isn't reported as a failure.
    func cancelProcessing(because reason: String = "stopped by you") {
        setAsideCurrent(because: reason)
        Announcer.post("The recording is under Needs Attention, \(reason).")
    }

    /// Parks the recording waiting on the participant review under Needs Attention and
    /// starts a new one, for a call that comes in before the user has named the last.
    /// The transcript is already saved, so naming it later skips straight to review.
    func nameLaterAndRecord(_ source: RecordingSource) async {
        setAsideCurrent(because: Self.waitingForNames)
        await start(source: source)
    }

    private func setAsideCurrent(because reason: String) {
        guard isProcessing else { return }
        processingAll = false
        processingTask?.cancel()
        // A retry may still be waiting on an earlier run, with no task of its own yet.
        unwinding = processingTask ?? unwinding
        processingTask = nil
        if let inFlight { setAside(inFlight, because: reason) }
        inFlight = nil
        state = .idle
    }

    /// Clears a failure message the user has read.
    func dismissFailure() {
        if case .failed = state { state = .idle }
        failedToStart = false
    }

    func dismissSave() {
        saveClearTask?.cancel()
        saveClearTask = nil
        lastSave = nil
    }

    func retry(_ session: RecordingSession) async {
        guard !isBusy else { return }
        needsAttention.removeAll { $0 === session }
        state = .processing(.transcribing)
        await process(session)
    }

    /// Works through Needs Attention one recording at a time until the list is done or
    /// the user cancels. Each recording still stops for participant review.
    func processAll() async {
        guard !isBusy else { return }
        processingAll = true
        defer { processingAll = false }
        // Re-checked each turn: the user may cancel, or discard one still waiting.
        for session in needsAttention where processingAll && needsAttention.contains(where: { $0 === session }) {
            await retry(session)
        }
    }

    func discard(_ session: RecordingSession) async {
        guard needsAttention.contains(where: { $0 === session }) else { return }
        needsAttention.removeAll { $0 === session }
        if case .failed = state, !failedToStart { state = .idle }
        // A cancelled run may still be reading these files.
        await finishUnwinding()
        session.deleteRecording()
    }

    /// Parks a recording under Needs Attention, which is where it's reported: the row
    /// says why, so no separate failure message repeats it.
    private func setAside(_ session: RecordingSession, because reason: String) {
        session.setAsideReason = reason
        guard !needsAttention.contains(where: { $0 === session }) else { return }
        needsAttention.append(session)
        needsAttention.sort { $0.startedAt > $1.startedAt }
    }

    private func finishUnwinding() async {
        await unwinding?.value
        unwinding = nil
    }

    func stop() async {
        guard let session = current else { return }
        current = nil
        state = .finishing
        detectionTask?.cancel()
        detectionTask = nil
        session.detectedParticipants = participantAccumulator.resolved()
        activityMonitor.stop()
        levels.stop()
        micCapture.stop()
        await systemCapture.stop()
        session.finishedAt = Date()
        do {
            try session.advance(to: .recorded)
        } catch {
            // The audio is still on disk; the next launch rebuilds the session from it.
            NSLog("Couldn't record session progress: \(error)")
        }
        await process(session)
    }

    /// Auto-detection saw a call app quit. Only a recording of that call stops: manual
    /// and in-person recordings have no target app, so quitting Slack or a browser
    /// leaves them running. A quiet mic (`nil`) is ignored: while recording, our own
    /// engine holds the mic, so it only goes quiet when that engine fails, and the
    /// user has already been warned to restart.
    func endDetectedCall(app bundleID: String?) async {
        guard current != nil, let bundleID, bundleID == currentTarget else { return }
        await stop()
    }

    private func process(_ session: RecordingSession) async {
        inFlight = session
        failedToStart = false
        // The transcriber isn't safe to run twice at once, and a retry reads the same files.
        await finishUnwinding()
        // Cancelled while waiting. Checking `inFlight` too stops a retry that was
        // cancelled and superseded from running alongside the newer one.
        guard inFlight === session, isProcessing || state == .finishing else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.transcribeAndWrite(session)
        }
        processingTask = task
        await task.value
        // A cancel followed by a retry installs a newer task; leave that one alone.
        if processingTask == task { processingTask = nil }
    }

    private func startParticipantDetection(target: String) {
        detectionTask = Task { [weak self] in
            while !Task.isCancelled {
                let found = await self?.participantDetector.detect(targetBundleID: target) ?? []
                self?.participantAccumulator.record(found)
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private func transcribeAndWrite(_ session: RecordingSession) async {
        let pipeline = NotePipeline(
            transcript: TranscriptBuilder(transcriber: transcriber, diarizer: diarizer),
            summarize: { [settings] segments in await Summary.of(segments: segments, settings: settings) },
            confirmRoster: confirmRoster
        )
        let input = NotePipeline.Input(
            session: session,
            model: settings.model,
            // An in-person meeting has no second track, so diarization is the only thing
            // that can tell the room's voices apart — always run it there.
            diarize: settings.diarize || !session.source.usesSystemAudio,
            summaryEnabled: settings.summaryEnabled,
            detectedParticipants: session.detectedParticipants,
            outputFolder: settings.resolveOutputFolder()
        )

        // Once cancelled, this task may still be unwinding while the user has moved on
        // (retried, or started another call), so it must not touch shared state.
        do {
            let outcome = try await pipeline.run(input) { [weak self] stage in
                guard !Task.isCancelled else { return }
                self?.state = .processing(stage)
            }
            guard !Task.isCancelled else { return }
            switch outcome {
            case .saved(let noteURL, let folder):
                inFlight = nil
                do {
                    try session.advance(to: .noted)
                } catch {
                    NSLog("Couldn't mark session noted: \(error)")
                }
                history.add(session)
                let warnings = [
                    session.summaryFailure.map { "Saved without a summary: \($0)." },
                    archiveOrDeleteAudio(for: session),
                ].compactMap { $0 }
                confirmSave(
                    folder: folder, noteURL: noteURL,
                    warning: warnings.isEmpty ? nil : warnings.joined(separator: " "))
                state = .idle
            case .deleted:
                inFlight = nil
                session.deleteRecording()
                state = .idle
            case .folderMissing:
                // The menu's folder banner asks for a new one; the row says why.
                inFlight = nil
                setAside(session, because: "notes folder missing")
                settings.revalidateFolders()
                state = .idle
                Announcer.post("The notes folder is missing. Choose one, then process the recording again.")
            }
        } catch {
            guard !Task.isCancelled else { return }
            NSLog("Processing failed: \(error)")
            inFlight = nil
            let stage = if case .processing(let stage) = state { stage.title.lowercased() } else { "processing" }
            setAside(session, because: "failed while \(stage)")
            state = .idle
            Announcer.post(
                "The \(session.source.displayName) recording failed while \(stage). It's under Needs Attention to try again."
            )
        }
    }

    /// Keeps the recording in Application Support if archiving fails, so audio
    /// the user asked to keep is never lost. Returns a warning when that happens.
    private func archiveOrDeleteAudio(for session: RecordingSession) -> String? {
        guard settings.keepAudio else {
            session.deleteRecording()
            return nil
        }
        // Keep audio without a folder is a choice Settings explains (it stays in the
        // app's Library folder), so it isn't warned about after every note.
        guard let folder = settings.resolveAudioFolder() else { return nil }
        do {
            try AudioArchiver.archive(session, to: folder, format: settings.audioFilenameFormat)
            session.deleteRecording()
            return nil
        } catch {
            NSLog("Audio archive failed: \(error)")
            return "Couldn't copy the audio to \(folder.lastPathComponent). It's kept in the app's Library folder."
        }
    }

    private func confirmSave(folder: URL, noteURL: URL?, warning: String?) {
        lastSave = SaveConfirmation(noteURL: noteURL, folderName: folder.lastPathComponent, warning: warning)
        saveClearTask?.cancel()
        saveClearTask = nil
        Announcer.post(
            warning.map { "Note saved to \(folder.lastPathComponent). \($0)" }
                ?? "Note saved to \(folder.lastPathComponent).")
    }

    /// The menu was opened. A plain save confirmation fades a few seconds after it has
    /// been seen, not after it was made: notes usually finish while the menu is closed.
    /// A warning stays until the user dismisses it.
    func saveConfirmationSeen() {
        guard let lastSave, lastSave.warning == nil, saveClearTask == nil else { return }
        saveClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            if Task.isCancelled { return }
            self?.lastSave = nil
            self?.saveClearTask = nil
        }
    }

    private func reportInterruption(_ issue: CaptureIssue) -> @Sendable (Error) -> Void {
        { [weak self] error in
            NSLog("Capture interrupted: \(error)")
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.captureWarning = issue
                Announcer.post("\(issue.title). \(issue.detail)")
            }
        }
    }

    /// Closes the audio of a call still being recorded, so quitting mid-call leaves
    /// intact files that show under Needs Attention on the next launch. Processing is
    /// left for then: the quit shouldn't wait on a transcription.
    func finishForQuit() async {
        guard let session = current else { return }
        // Cleared before the first await, as in `stop()`, so a Stop arriving
        // mid-teardown can't finalize the same files a second time.
        current = nil
        session.detectedParticipants = participantAccumulator.resolved()
        await teardown()
        session.finishedAt = Date()
        do {
            try session.advance(to: .recorded)
        } catch {
            NSLog("Couldn't record session progress before quitting: \(error)")
        }
    }

    private func teardown() async {
        detectionTask?.cancel()
        detectionTask = nil
        activityMonitor.stop()
        levels.stop()
        await systemCapture.stop()
        micCapture.stop()
        current = nil
    }
}

/// Something wrong with the audio mid-recording, worded once for the menu and the panel.
enum CaptureIssue: Equatable, Sendable {
    case micStopped
    case callAudioStopped
    /// The mic is recording but hears nothing: muted, or the wrong input device.
    case micSilent

    var title: String {
        switch self {
        case .micStopped: "Microphone stopped"
        case .callAudioStopped: "Call audio stopped"
        case .micSilent: "Microphone is silent"
        }
    }

    var detail: String {
        switch self {
        case .micStopped:
            "Anything you say from now on is missed. Stop to save what was captured."
        case .callAudioStopped:
            "The rest of the call is missed. Stop to save what was captured."
        case .micSilent:
            "Check it isn't muted and the right input is selected."
        }
    }
}

#if DEBUG
    extension RecordingController {
        /// Puts the menu into a given state for the screenshot catalog without touching
        /// audio hardware. Debug builds only.
        func stageForScreenshots(
            _ state: State,
            lastSave: SaveConfirmation? = nil,
            needsAttention: [RecordingSession] = [],
            failedToStart: Bool = false,
            lastSource: RecordingSource = .manual,
            captureWarning: CaptureIssue? = nil
        ) {
            self.state = state
            self.lastSave = lastSave
            self.needsAttention = needsAttention
            self.failedToStart = failedToStart
            self.lastSource = lastSource
            self.captureWarning = captureWarning
        }
    }
#endif
