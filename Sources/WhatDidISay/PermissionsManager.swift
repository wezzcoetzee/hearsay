import Foundation
import AVFoundation
import CoreGraphics
import ScreenCaptureKit
import AppKit
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

    @Published private(set) var microphone: Status = .unknown
    @Published private(set) var screenRecording: Status = .unknown

    var allGranted: Bool { microphone.isGranted && screenRecording.isGranted }

    /// Mic-only sources don't need Screen Recording, so they shouldn't be blocked on it.
    func isGranted(for source: RecordingSource) -> Bool {
        microphone.isGranted && (!source.usesSystemAudio || screenRecording.isGranted)
    }

    func requestAll() async {
        await requestMicrophone()
        await requestScreenRecording()
    }

    func refresh() {
        microphone = Self.microphoneStatus()
        screenRecording = CGPreflightScreenCaptureAccess() ? .granted : .denied
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

    private static func microphoneStatus() -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .unknown
        default: return .denied
        }
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
