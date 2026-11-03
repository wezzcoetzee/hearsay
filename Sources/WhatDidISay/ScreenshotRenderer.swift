#if DEBUG
import SwiftUI
import AppKit

/// Renders the real views with seeded demo data to PNGs, then exits. Drives the
/// App Store and README images: `WhatDidISay -renderScreenshots <dir>`.
/// Nothing is recorded and nothing on disk is read or written besides the PNGs.
@MainActor
enum ScreenshotRenderer {
    static var outputDirectory: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-renderScreenshots"), args.indices.contains(flag + 1) else { return nil }
        return URL(fileURLWithPath: args[flag + 1], isDirectory: true)
    }

    static func run(into directory: URL) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .darkAqua)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let settings = Settings()
        let permissions = PermissionsManager()
        let recorder = RecordingController(settings: settings, permissions: permissions)
        let onboarding = OnboardingController(permissions: permissions, settings: settings)
        recorder.history.seedForScreenshots(demoHistory)
        settings.seedForScreenshots(outputFolder: "/Users/demo/Notes/Meetings")

        func menu() -> some View {
            MenuContent(recorder: recorder, settings: settings, permissions: permissions,
                        history: recorder.history, levels: recorder.levels, onboarding: onboarding)
        }
        // `MenuContent` refreshes permissions as it appears, so seed them after.
        let reseed = { permissions.seedForScreenshots() }

        recorder.stageForScreenshots(.recording(since: Date().addingTimeInterval(-1_394)))
        recorder.levels.stageForScreenshots(mic: 0.62, system: 0.81)
        render(menu(), name: "menu-recording", into: directory, before: reseed)

        recorder.stageForScreenshots(.idle)
        render(menu(), name: "menu-history", into: directory, before: reseed)

        let confirmation = ConfirmationController()
        confirmation.stageForScreenshots(source: .slack, countdown: 12, cloudActive: false)
        render(ConfirmationView(controller: confirmation).frame(width: 360), name: "confirmation", into: directory)

        render(ParticipantReviewView(request: demoRoster, onDone: { _ in }, onDelete: {}).frame(width: 380),
               name: "review", into: directory)

        exit(0)
    }

    private static func render(_ view: some View, name: String, into directory: URL, before: () -> Void = {}) {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.setContentSize(hosting.fittingSize)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        before()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        window.setContentSize(hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        let size = hosting.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: directory.appendingPathComponent("\(name).png"))
    }

    private static let demoHistory: [HistoryEntry] = [
        ("Slack Huddle", -3_600), ("Google Meet", -26_000), ("In Person", -90_000),
        ("Teams Call", -180_000), ("Slack Huddle", -260_000)
    ].map { source, offset in
        HistoryEntry(id: UUID(), date: Date().addingTimeInterval(TimeInterval(offset)), source: source,
                     notePath: nil, recordingPath: nil, segmentCount: 0)
    }

    private static let demoRoster = RosterReview(
        voices: [
            VoiceCandidate(label: "Me", suggestion: "Wesley", sample: "Let's lock the launch date before Friday."),
            VoiceCandidate(label: "Speaker 1", suggestion: "Priya", sample: "Design review is done, QA starts Monday."),
            VoiceCandidate(label: "Speaker 2", suggestion: "", sample: "I can own the release notes.")
        ],
        others: ["Marcus Chen"]
    )
}
#endif
