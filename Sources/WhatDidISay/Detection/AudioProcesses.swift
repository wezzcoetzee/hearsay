import Foundation
import CoreAudio
import Darwin

/// Per-process audio state (macOS 14.4+). Slack and Teams are Electron apps that often
/// play and record from a helper process, so a bundle's audio activity is the activity of
/// every audio process whose executable lives inside it.
@available(macOS 14.4, *)
enum AudioProcesses {
    enum Direction {
        case input, output

        fileprivate var selector: AudioObjectPropertySelector {
            switch self {
            case .input: return kAudioProcessPropertyIsRunningInput
            case .output: return kAudioProcessPropertyIsRunningOutput
            }
        }
    }

    /// True when any audio process inside the app bundle at `bundlePath` is running `direction`.
    static func isRunning(_ direction: Direction, inBundleAt bundlePath: String) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: direction.selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return objects(inBundleAt: bundlePath).contains { object in
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr && value != 0
        }
    }

    private static func objects(inBundleAt bundlePath: String) -> [AudioObjectID] {
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
        let bundlePrefix = bundlePath + "/"
        return objects.filter { object in
            var pid: pid_t = 0
            var size = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &size, &pid) == noErr else { return false }
            return executablePath(forPID: pid)?.hasPrefix(bundlePrefix) ?? false
        }
    }

    private static func executablePath(forPID pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer[0..<Int(length)], as: UTF8.self)
    }
}
