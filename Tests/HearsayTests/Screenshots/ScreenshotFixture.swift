import AppKit
import Foundation

@testable import Hearsay

/// The app's models wired up in isolation: preferences in a throwaway defaults
/// suite, a keychain service nothing else uses, and history, recordings, notes and
/// audio under a temp folder. Nothing here reads or writes the user's real data.
@MainActor
final class ScreenshotFixture {
    typealias Status = PermissionsManager.Status

    /// What the permission probe answers; mutable so a scene can set it up front.
    private final class Grants {
        var microphone: Status
        var screenRecording: Status
        init(microphone: Status, screenRecording: Status) {
            self.microphone = microphone
            self.screenRecording = screenRecording
        }
    }

    let root: URL
    let settings: Settings
    let permissions: PermissionsManager
    let history: RecordingHistory
    let recorder: RecordingController
    let onboarding: OnboardingController

    private let suiteName: String

    /// 9:41 on a weekday morning, so timestamps read the same on every run.
    static let morning = Calendar.current.date(
        from: DateComponents(year: 2026, month: 11, day: 3, hour: 9, minute: 41))!

    init(microphone: Status = .granted, screenRecording: Status = .granted, vault: Bool = true) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Hearsay-screenshots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        suiteName = "com.wcoetzee.hearsay.screenshots.\(UUID().uuidString)"
        settings = Settings(
            defaults: UserDefaults(suiteName: suiteName)!,
            keychain: Keychain(service: "com.wcoetzee.hearsay.screenshots"))
        settings.hasAcknowledgedConsent = true

        let grants = Grants(microphone: microphone, screenRecording: screenRecording)
        permissions = PermissionsManager { (grants.microphone, grants.screenRecording) }
        permissions.refresh()

        history = RecordingHistory(fileURL: root.appendingPathComponent("history.json"))
        recorder = RecordingController(
            settings: settings, permissions: permissions, history: history,
            recordingsFolder: root.appendingPathComponent("Recordings", isDirectory: true))
        onboarding = OnboardingController(permissions: permissions, settings: settings)

        if vault { settings.useOutputFolder(try folder("Notes")) }
    }

    func folder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A finished call, `minutesAgo` before 9:41, with a real note file behind it.
    func session(_ source: RecordingSource, minutesAgo: Int, lasting minutes: Int) -> RecordingSession {
        let session = RecordingSession(
            source: source,
            startedAt: Self.morning.addingTimeInterval(TimeInterval(-minutesAgo * 60)),
            in: root.appendingPathComponent("Recordings", isDirectory: true))
        session.finishedAt = session.startedAt.addingTimeInterval(TimeInterval(minutes * 60))
        return session
    }

    func addHistory() throws {
        let notes = try folder("Notes")
        let calls: [(RecordingSource, Int, [String])] = [
            (.inPerson, 60 * 22, ["Me", "Dana", "Sam", "Lee"]), (.teams, 60 * 4, ["Me", "Ana Ruiz", "Ben Ode", "Cy Tan", "Dee Moss", "Eli Ray", "Fay Lu"]),
            (.googleMeet, 95, ["Me", "Tom Hill", "Jo Park"]), (.slack, 20, ["Me", "Priya Shah", "Marcus Lee"]),
        ]
        for (source, minutesAgo, people) in calls {
            let call = session(source, minutesAgo: minutesAgo, lasting: 25)
            call.participants = people
            let note = notes.appendingPathComponent("\(source.rawValue).md")
            FileManager.default.createFile(atPath: note.path, contents: Data())
            call.noteURL = note
            history.add(call)
        }
    }

    func noteURL() throws -> URL {
        let note = try folder("Notes").appendingPathComponent("2026-11-03 0941 Slack Huddle - Launch plan.md")
        FileManager.default.createFile(atPath: note.path, contents: Data())
        return note
    }

    func cleanUp() {
        // Deletes the throwaway keychain item a cloud scene may have written.
        settings.anthropicAPIKey = ""
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}
