import AVFoundation
import AppKit
import Combine
import CoreGraphics
import Foundation
import ScreenCaptureKit

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
            await requestScreenRecording()
            if !screenRecording.isGranted { openSettings(.screenRecording) }
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
        let microphone: Status =
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: .granted
            case .notDetermined: .unknown
            default: .denied
            }
        return (microphone, CGPreflightScreenCaptureAccess() ? .granted : .denied)
    }
}

#if DEBUG
    extension PermissionsManager {
        func seedForScreenshots() {
            microphone = .granted
            screenRecording = .granted
        }
    }
#endif
