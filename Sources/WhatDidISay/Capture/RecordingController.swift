import Foundation
import Combine
import AppKit

@MainActor
final class RecordingController: ObservableObject {
    enum State: Equatable {
        case idle
        case recording(since: Date)
        case finishing
        case processing(Stage)
        case failed(String)

        enum Stage: String {
            case transcribing = "Transcribing"
            case identifyingSpeakers = "Identifying speakers"
            case summarizing = "Summarizing"
            case reviewing = "Confirming participants"
            case saving = "Saving note"
        }
    }

    struct SaveConfirmation: Equatable {
        let noteURL: URL?
        let folderName: String
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastSession: RecordingSession?
    @Published private(set) var lastSave: SaveConfirmation?
    private var saveClearTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?

    let settings: Settings
    let permissions: PermissionsManager
    let history = RecordingHistory()

    private let systemCapture = SystemAudioCapture()
    private let micCapture = MicCapture()
    private let transcriber = TranscriptionService()
    private let diarizer = Diarizer()
    private let activityMonitor = CallActivityMonitor()
    private let participantDetector = ParticipantDetector()
    private let browserDetector = BrowserCallDetector()
    private var current: RecordingSession?
    private var currentTarget: String?
    private var detectedParticipants = Set<String>()
    private var detectionTask: Task<Void, Never>?

    /// Set by AppCoordinator to present the review dialog and return the confirmed roster,
    /// or `nil` when the user chooses to delete the call.
    var confirmParticipants: (([String]) async -> [String]?)?

    init(settings: Settings, permissions: PermissionsManager) {
        self.settings = settings
        self.permissions = permissions
        activityMonitor.onEnded = { [weak self] in
            Task { await self?.stop() }
        }
    }

    private func bundleID(for source: RecordingSource) -> String? {
        if source == .googleMeet, let host = browserDetector.meetBrowserBundleID() {
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
        case .idle, .failed: return false
        }
    }

    var isProcessing: Bool {
        if case .processing = state { return true }
        return false
    }

    func toggle() async {
        if isRecording {
            await stop()
        } else {
            await start(source: .manual)
        }
    }

    func start(source: RecordingSource) async {
        guard !isBusy else { return }

        saveClearTask?.cancel()
        lastSave = nil
        permissions.refresh()
        guard permissions.allGranted else {
            state = .failed("Grant Microphone and Screen Recording, then relaunch.")
            return
        }
        guard settings.hasOutputFolder else {
            state = .failed("Choose a notes folder before recording, so this call has somewhere to save.")
            return
        }

        let session = RecordingSession(source: source)
        let target = bundleID(for: source)
        do {
            try session.prepareDirectory()
            try await systemCapture.start(writingTo: session.systemAudioURL, targetBundleID: target)
            try micCapture.start(writingTo: session.micAudioURL)
            current = session
            currentTarget = target
            detectedParticipants = []
            state = .recording(since: session.startedAt)
            if let target {
                activityMonitor.start(bundleID: target)
                startParticipantDetection(target: target)
            }
        } catch {
            await teardown()
            NSLog("Recording start failed: \(error)")
            state = .failed("Couldn't start recording. Another app may be using the microphone or system audio. Try again.")
        }
    }

    func cancelProcessing() {
        guard isProcessing else { return }
        processingTask?.cancel()
        processingTask = nil
        state = .idle
    }

    func stop() async {
        guard let session = current else { return }
        current = nil
        state = .finishing
        detectionTask?.cancel()
        detectionTask = nil
        activityMonitor.stop()
        micCapture.stop()
        await systemCapture.stop()
        session.finishedAt = Date()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.transcribeAndWrite(session)
        }
        processingTask = task
        await task.value
        processingTask = nil
    }

    private func startParticipantDetection(target: String) {
        detectionTask = Task { [weak self] in
            while !Task.isCancelled {
                let found = await self?.participantDetector.detect(targetBundleID: target) ?? []
                self?.detectedParticipants.formUnion(found)
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private func transcribeAndWrite(_ session: RecordingSession) async {
        let pipeline = NotePipeline(
            transcript: TranscriptBuilder(transcriber: transcriber, diarizer: diarizer),
            summarize: { [settings] segments in await Summary.of(segments: segments, settings: settings) },
            confirmParticipants: confirmParticipants
        )
        let input = NotePipeline.Input(
            session: session,
            model: settings.model,
            diarize: settings.diarize,
            summaryEnabled: settings.summaryEnabled,
            detectedParticipants: Array(detectedParticipants),
            outputFolder: settings.resolveOutputFolder()
        )

        do {
            let outcome = try await pipeline.run(input) { [weak self] stage in
                self?.state = .processing(stage.recordingStage)
            }
            switch outcome {
            case .saved(let noteURL, let folder):
                lastSession = session
                history.add(session)
                archiveOrDeleteAudio(for: session)
                confirmSave(folder: folder, noteURL: noteURL)
                state = .idle
            case .deleted:
                session.deleteRecording()
                state = .idle
            case .folderMissing:
                lastSession = session
                history.add(session)
                state = .failed("Couldn't save the note: the notes folder is missing. Pick one, then save this call again.")
            }
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            lastSession = session
            NSLog("Processing failed: \(error)")
            state = .failed("Couldn't finish processing this recording. The audio is still on your Mac. Try again.")
        }
    }

    /// Keeps the recording in Application Support if archiving fails, so audio
    /// the user asked to keep is never lost.
    private func archiveOrDeleteAudio(for session: RecordingSession) {
        guard settings.keepAudio, let folder = settings.resolveAudioFolder() else {
            session.deleteRecording()
            return
        }
        do {
            try AudioArchiver.archive(session, to: folder, format: settings.audioFilenameFormat)
            session.deleteRecording()
        } catch {
            NSLog("Audio archive failed: \(error)")
        }
    }

    private func confirmSave(folder: URL, noteURL: URL?) {
        lastSave = SaveConfirmation(noteURL: noteURL, folderName: folder.lastPathComponent)
        saveClearTask?.cancel()
        saveClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            if Task.isCancelled { return }
            self?.lastSave = nil
        }
    }

    private func teardown() async {
        detectionTask?.cancel()
        detectionTask = nil
        activityMonitor.stop()
        await systemCapture.stop()
        micCapture.stop()
        current = nil
    }
}

private extension NotePipeline.Stage {
    var recordingStage: RecordingController.State.Stage {
        switch self {
        case .transcribing: .transcribing
        case .identifyingSpeakers: .identifyingSpeakers
        case .summarizing: .summarizing
        case .reviewing: .reviewing
        case .saving: .saving
        }
    }
}
