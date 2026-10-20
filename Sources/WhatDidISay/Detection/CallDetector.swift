import Foundation
import CoreAudio
import AppKit
import Combine

@MainActor
final class CallDetector: ObservableObject {
    @Published private(set) var micActive = false

    var onDetect: ((RecordingSource) -> Void)?
    /// A call looks over: the bundle id of the call app that quit, or `nil` when the
    /// mic went quiet.
    var onEnd: ((String?) -> Void)?

    private let browserDetector = BrowserCallDetector()
    private let queue = DispatchQueue(label: "com.wcoetzee.whatdidisay.calldetector")
    private var inputDevice = AudioDeviceID(kAudioObjectUnknown)
    private var runningListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var coldStopTask: Task<Void, Never>?
    private var isRunning = false

    private var terminationObserver: NSObjectProtocol?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        inputDevice = Self.defaultInputDevice()
        installRunningListener()
        installDeviceChangeListener()
        installTerminationObserver()
        micActive = isMicRunning()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        removeRunningListener()
        removeDeviceChangeListener()
        removeTerminationObserver()
        coldStopTask?.cancel()
        coldStopTask = nil
    }

    private func installTerminationObserver() {
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor in
                guard let self, let bundleID,
                      RecordingSource.source(forBundleID: bundleID) != nil
                        || RecordingSource.browserBundleIDs.contains(bundleID) else { return }
                self.onEnd?(bundleID)
            }
        }
    }

    private func removeTerminationObserver() {
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
    }

    private func handleMicStateChange() {
        let active = isMicRunning()
        guard active != micActive else { return }
        micActive = active

        if active {
            coldStopTask?.cancel()
            coldStopTask = nil
            if let source = detectTargetSource() {
                onDetect?(source)
            }
        } else {
            scheduleColdStop()
        }
    }

    private func scheduleColdStop() {
        coldStopTask?.cancel()
        coldStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled, !self.isMicRunning() else { return }
            self.onEnd?(nil)
        }
    }

    private func detectTargetSource() -> RecordingSource? {
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           let match = RecordingSource.source(forBundleID: front) {
            return match
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        if let native = RecordingSource.detectable.first(where: { source in
            source.bundleIDs.contains(where: running.contains)
        }) {
            return native
        }
        return browserDetector.meetBrowserBundleID() != nil ? .googleMeet : nil
    }

    private func installRunningListener() {
        guard inputDevice != AudioDeviceID(kAudioObjectUnknown) else { return }
        var address = Self.runningAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.handleMicStateChange() }
        }
        runningListener = block
        AudioObjectAddPropertyListenerBlock(inputDevice, &address, queue, block)
    }

    private func removeRunningListener() {
        guard let block = runningListener, inputDevice != AudioDeviceID(kAudioObjectUnknown) else { return }
        var address = Self.runningAddress
        AudioObjectRemovePropertyListenerBlock(inputDevice, &address, queue, block)
        runningListener = nil
    }

    private func installDeviceChangeListener() {
        var address = Self.defaultInputAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.rebindInputDevice() }
        }
        deviceListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
    }

    private func removeDeviceChangeListener() {
        guard let block = deviceListener else { return }
        var address = Self.defaultInputAddress
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
        deviceListener = nil
    }

    private func rebindInputDevice() {
        removeRunningListener()
        inputDevice = Self.defaultInputDevice()
        installRunningListener()
        handleMicStateChange()
    }

    private func isMicRunning() -> Bool {
        guard inputDevice != AudioDeviceID(kAudioObjectUnknown) else { return false }
        var address = Self.runningAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(inputDevice, &address, 0, nil, &size, &value)
        return status == noErr && value != 0
    }

    private static func defaultInputDevice() -> AudioDeviceID {
        var address = defaultInputAddress
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    private static var runningAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var defaultInputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
