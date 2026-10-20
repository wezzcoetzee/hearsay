import Foundation
import Combine

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

        detector.onDetect = { [weak self] source in
            guard let self, !self.recorder.isBusy else { return }
            // Permissions may have changed in System Settings since we last looked.
            self.permissions.refresh()
            guard self.permissions.allGranted else { return }
            self.confirmation.present(source: source)
        }
        confirmation.onConfirm = { [weak self] source in
            Task { await self?.recorder.start(source: source) }
        }
        confirmation.onTurnOffAutoDetect = { [weak self] in
            self?.settings.autoDetect = false
        }
        confirmation.isCloudSummaryActive = { [weak self] in
            guard let self else { return false }
            return self.settings.summaryEnabled && self.settings.summaryBackend == .cloud
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
            .sink { [weak self] state in self?.controlPanel.update(for: state) }
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
}
