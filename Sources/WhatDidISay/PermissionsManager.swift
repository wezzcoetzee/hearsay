import Foundation
import AVFoundation
import CoreGraphics
import ScreenCaptureKit
import AppKit
import ApplicationServices
import Combine

@MainActor
final class PermissionsManager: ObservableObject {
    enum Status {
        case unknown, granted, denied

        var isGranted: Bool { self == .granted }
    }

    enum Pane {
        case microphone, screenRecording

        var urlString: String {
            switch self {
            case .microphone:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            case .screenRecording:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            }
        }
    }

    /// Reads what macOS currently allows. Screenshots swap in fixed answers.
    typealias Probe = @MainActor () -> (microphone: Status, screenRecording: Status)

    @Published private(set) var microphone: Status = .unknown
    @Published private(set) var screenRecording: Status = .unknown
    /// Set once the user asks for Screen Recording this launch. macOS only reports it
    /// as allowed after a relaunch, so from then on every surface offers that relaunch.
    @Published private(set) var screenRecordingRequested = false

    private let probe: Probe

    init(probe: @escaping Probe = PermissionsManager.systemStatus) {
        self.probe = probe
    }

    var allGranted: Bool { microphone.isGranted && screenRecording.isGranted }

    /// Mic-only sources don't need Screen Recording, so they shouldn't be blocked on it.
    func isGranted(for source: RecordingSource) -> Bool {
        microphone.isGranted && (!source.usesSystemAudio || screenRecording.isGranted)
    }

    func refresh() {
        (microphone, screenRecording) = probe()
    }

    /// Asks macOS first, because an app that has never asked isn't listed in System
    /// Settings, so sending the user there would show them nothing to switch on.
    func request(_ pane: Pane) async {
        switch pane {
        case .microphone:
            if microphone == .unknown {
                await requestMicrophone()
            } else {
                openSettings(.microphone)
            }
        case .screenRecording:
            screenRecordingRequested = true
            await requestScreenRecording()
            if !screenRecording.isGranted { openSettings(.screenRecording) }
        }
    }

    /// What the button that fixes a missing permission says: "Allow…" while macOS can
    /// still ask, "Open System Settings" once the answer was no.
    static func actionTitle(for pane: Pane, status: Status) -> String {
        pane == .microphone && status == .denied ? "Open System Settings" : "Allow…"
    }

    /// Optional: lets the app read names off the call window. macOS shows its own
    /// prompt the first time; after that, only the Privacy pane can change it.
    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true]
        guard !AXIsProcessTrustedWithOptions(options as CFDictionary) else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openSettings(_ pane: Pane) {
        if let url = URL(string: pane.urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func requestMicrophone() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphone = .granted
        case .notDetermined:
            microphone = await AVCaptureDevice.requestAccess(for: .audio) ? .granted : .denied
        default:
            microphone = .denied
        }
    }

    func requestScreenRecording() async {
        if CGPreflightScreenCaptureAccess() {
            screenRecording = .granted
            return
        }
        _ = CGRequestScreenCaptureAccess()
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            screenRecording = .granted
        } catch {
            screenRecording = .denied
        }
    }

    static func systemStatus() -> (microphone: Status, screenRecording: Status) {
        let microphone: Status = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .unknown
        default: .denied
        }
        return (microphone, CGPreflightScreenCaptureAccess() ? .granted : .denied)
    }
}

#if DEBUG
extension PermissionsManager {
    /// The state after asking for Screen Recording, for the screenshot catalog.
    func stageScreenRecordingRequested() { screenRecordingRequested = true }
}
#endif
