import Foundation
import CoreAudio
import AppKit

@MainActor
final class CallDetector {
    var onDetect: ((RecordingSource) -> Void)?
    /// A call looks over: the bundle id of the call app that quit, or `nil` when the
    /// mic went quiet. While we record, our own mic engine keeps the input device
    /// running, so `nil` only fires when no recording holds the mic: it can withdraw a
    /// pending prompt but never ends a recording. Recordings end on the app quitting
    /// or `CallActivityMonitor` seeing the call's audio stop.
    var onEnd: ((String?) -> Void)?

    private let browserDetector = BrowserCallDetector()
    private let queue = DispatchQueue(label: "com.wcoetzee.whatdidisay.calldetector")
    private var inputDevice = AudioDeviceID(kAudioObjectUnknown)
    private var runningListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var coldStopTask: Task<Void, Never>?
    private var detectTask: Task<Void, Never>?
    private var micActive = false
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
        detectTask?.cancel()
        detectTask = nil
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
            detectTask?.cancel()
            // The Meet check is slow; a mic that goes quiet meanwhile cancels the task.
            detectTask = Task { [weak self] in
                guard let self, let source = await self.detectTargetSource(), !Task.isCancelled else { return }
                self.onDetect?(source)
            }
        } else {
            detectTask?.cancel()
            detectTask = nil
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

    /// Which call the live mic most likely belongs to. A frontmost call app is the
    /// strongest signal, then a browser with a Meet tab, and only then a call app idling
    /// in the background (which must itself be using the mic, or Slack merely running
    /// would claim every Meet call).
    private func detectTargetSource() async -> RecordingSource? {
        await Self.resolveSource(
            frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                .flatMap(RecordingSource.source(forBundleID:)),
            hasMeetTab: { await self.browserDetector.meetBrowserBundleID() != nil },
            backgroundCallApp: Self.backgroundCallAppUsingMic
        )
    }

    /// The source-ordering rule, with the expensive checks passed in so each runs only
    /// when the stronger ones came up empty.
    static func resolveSource(
        frontmost: RecordingSource?,
        hasMeetTab: () async -> Bool,
        backgroundCallApp: () -> RecordingSource?
    ) async -> RecordingSource? {
        if let frontmost { return frontmost }
        if await hasMeetTab() { return .googleMeet }
        return backgroundCallApp()
    }

    private static func backgroundCallAppUsingMic() -> RecordingSource? {
        let running = NSWorkspace.shared.runningApplications
        return RecordingSource.detectable.first { source in
            running.contains { app in
                guard let id = app.bundleIdentifier, source.bundleIDs.contains(id) else { return false }
                guard #available(macOS 14.4, *) else { return true }
                return app.bundleURL.map { AudioProcesses.isRunning(.input, inBundleAt: $0.path) } ?? false
            }
        }
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
