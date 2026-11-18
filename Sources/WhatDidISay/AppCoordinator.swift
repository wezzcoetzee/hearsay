import Combine
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    let settings: Settings
    let recorder: RecordingController
    let permissions = PermissionsManager()
    let detector = CallDetector()
    let confirmation = ConfirmationController()
    let onboarding: OnboardingController
    let participantReview = ParticipantReviewController()
    let controlPanel: RecordingControlPanelController

    private var bag = Set<AnyCancellable>()

    init() {
        let settings = Settings()
        self.settings = settings
        let recorder = RecordingController(settings: settings, permissions: permissions)
        self.recorder = recorder
        self.controlPanel = RecordingControlPanelController(levels: recorder.levels)
        self.onboarding = OnboardingController(permissions: permissions, settings: settings)

        let review = participantReview
        recorder.confirmRoster = { request in
            await review.review(request)
        }
        review.onNameLater = { [weak recorder] in
            recorder?.cancelProcessing(because: RecordingController.waitingForNames)
        }

        detector.onDetect = { [weak self] source in
            guard let self, !self.recorder.isRecording else { return }
            // Permissions may have changed in System Settings since we last looked.
            self.permissions.refresh()
            guard self.permissions.allGranted else { return }
            // Still say a call was seen while the last note finishes, so auto-detect
            // doesn't look broken; the prompt says what's holding it up instead.
            self.confirmation.present(source: source, blocker: self.callBlocker)
        }
        confirmation.onNameLaterAndRecord = { [weak self] source in
            Task { await self?.startFromPrompt(source) { await $0.nameLaterAndRecord(source) } }
        }
        confirmation.onConfirm = { [weak self] source in
            Task { await self?.startFromPrompt(source) { await $0.start(source: source) } }
        }
        confirmation.isCloudSummaryActive = { [weak self] in
            self?.settings.cloudSummaryActive ?? false
        }
        detector.onEnd = { [weak self] bundleID in
            self?.confirmation.withdraw(ifEndedBy: bundleID)
            Task { await self?.recorder.endDetectedCall(app: bundleID) }
        }

        controlPanel.onStop = { [weak self] in
            Task { await self?.recorder.stop() }
        }
        recorder.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.controlPanel.update(for: state, source: self.recorder.lastSource)
                // A recording started from the menu answers any prompt still up.
                if case .recording = state { self.confirmation.dismiss() }
                self.confirmation.refresh(blocker: self.callBlocker(for: state))
            }
            .store(in: &bag)
        recorder.$captureWarning
            .sink { [weak self] warning in self?.controlPanel.warning = warning }
            .store(in: &bag)
        // Only the flip matters (not the fifteen level updates a second): it badges the
        // menu-bar icon, and VoiceOver hears it once.
        recorder.levels.$micSilent
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] silent in
                guard let self else { return }
                self.objectWillChange.send()
                if silent, self.recorder.isRecording {
                    Announcer.post("\(CaptureIssue.micSilent.title). \(CaptureIssue.micSilent.detail)")
                }
            }
            .store(in: &bag)

        recorder.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &bag)

        permissions.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &bag)

        settings.$autoDetect
            .sink { [weak self] enabled in
                if enabled {
                    self?.detector.start()
                } else {
                    self?.detector.stop()
                    self?.confirmation.dismiss()
                }
            }
            .store(in: &bag)

        settings.$showRecordingPanel
            .sink { [weak self] enabled in self?.controlPanel.isEnabled = enabled }
            .store(in: &bag)

        // This init runs inside SwiftUI's scene-graph update (via @StateObject). Opening a
        // hosted window synchronously here nests a second graph update and SwiftUI aborts
        // the app, so show onboarding once launch has finished.
        Task { @MainActor [weak self] in
            self?.onboarding.presentIfNeeded()
        }
    }

    /// Starts a recording the prompt offered, and brings the prompt back to say so if
    /// capture didn't start: the prompt is gone and the menu usually closed.
    private func startFromPrompt(
        _ source: RecordingSource,
        _ start: (RecordingController) async -> Void
    ) async {
        await start(recorder)
        if recorder.failedToStart, case .failed(let reason) = recorder.state {
            confirmation.presentFailure(source: source, reason: reason)
        }
    }

    private var callBlocker: CallBlocker? { callBlocker(for: recorder.state) }

    /// Why a detected call can't be recorded right now, or `nil` when it can.
    private func callBlocker(for state: RecordingController.State) -> CallBlocker? {
        switch state {
        case .processing(.reviewing): .awaitingNames
        case .finishing, .processing: .savingLastNote
        case .idle, .failed, .recording: nil
        }
    }
}
