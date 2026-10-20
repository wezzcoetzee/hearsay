import Foundation
import CoreAudio
import AppKit
import Darwin

/// Watches whether a target app (Slack/Teams) is actively producing audio output.
/// While a huddle/call is live the app runs an output stream; when it ends the stream
/// stops. Unlike the microphone flag, this is not masked by our own recording.
///
/// Slack/Teams are Electron apps that often play audio from a helper process, so we
/// track every audio process whose executable lives inside the target app bundle.
@MainActor
final class CallActivityMonitor {
    var onEnded: (() -> Void)?

    private let queue = DispatchQueue(label: "com.wcoetzee.whatdidisay.callactivity")
    private var processObjects: [AudioObjectID] = []
    private var listener: AudioObjectPropertyListenerBlock?
    private var endTask: Task<Void, Never>?
    private var monitoring = false

    func start(bundleID: String) {
        guard #available(macOS 14.4, *), !monitoring else { return }
        guard let bundleURL = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID).first?.bundleURL else { return }

        let objects = Self.audioProcessObjects(inBundleAt: bundleURL.path)
        guard !objects.isEmpty else { return }

        processObjects = objects
        monitoring = true

        var address = Self.isRunningOutputAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.handleChange() }
        }
        listener = block
        for object in objects {
            AudioObjectAddPropertyListenerBlock(object, &address, queue, block)
        }
    }

    func stop() {
        guard monitoring else { return }
        monitoring = false
        if #available(macOS 14.4, *), let block = listener {
            var address = Self.isRunningOutputAddress
            for object in processObjects {
                AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
            }
        }
        listener = nil
        processObjects = []
        endTask?.cancel()
        endTask = nil
    }

    private func handleChange() {
        guard monitoring else { return }
        if isAnyRunningOutput() {
            endTask?.cancel()
            endTask = nil
        } else {
            scheduleEnd()
        }
    }

    private func scheduleEnd() {
        endTask?.cancel()
        endTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, !Task.isCancelled, self.monitoring, !self.isAnyRunningOutput() else { return }
            self.onEnded?()
        }
    }

    private func isAnyRunningOutput() -> Bool {
        guard #available(macOS 14.4, *) else { return true }
        var address = Self.isRunningOutputAddress
        for object in processObjects {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, value != 0 {
                return true
            }
        }
        return false
    }

    @available(macOS 14.4, *)
    private static var isRunningOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    @available(macOS 14.4, *)
    private static func audioProcessObjects(inBundleAt bundlePath: String) -> [AudioObjectID] {
        var listAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &listAddress, 0, nil, &dataSize) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &listAddress, 0, nil, &dataSize, &objects) == noErr else { return [] }

        var pidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return objects.filter { object in
            var pid: pid_t = 0
            var size = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &size, &pid) == noErr else { return false }
            return executablePath(forPID: pid)?.hasPrefix(bundlePath) ?? false
        }
    }

    private static func executablePath(forPID pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer[0..<Int(length)], as: UTF8.self)
    }
}
