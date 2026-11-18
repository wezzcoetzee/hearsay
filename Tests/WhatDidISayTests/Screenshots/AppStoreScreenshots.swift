import AppKit
import Foundation
import SwiftUI
import Testing
@testable import WhatDidISay

/// Mac App Store marketing screenshots: 1440 x 900 points, rendered at 2x to the
/// 2880 x 1800 App Store size. Each frame is a short headline beside the app's real
/// views, staged from the same throwaway fixtures as the screenshot catalog, so the
/// pictures can't drift from the app. Skipped unless `$APPSTORE_SCREENSHOTS_DIR` is
/// set; run it with `Scripts/appstore-screenshots.sh`.
@MainActor
@Suite struct AppStoreScreenshots {
    nonisolated static let outputDirectory = ProcessInfo.processInfo.environment["APPSTORE_SCREENSHOTS_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    }

    struct Frame {
        let id: String
        let headline: String
        let detail: String
        let ui: @MainActor (ScreenshotFixture) throws -> AnyView
    }

    @Test(.enabled(if: outputDirectory != nil))
    func renderFrames() async throws {
        let directory = try #require(Self.outputDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, frame) in Self.frames.enumerated() {
            let fixture = try ScreenshotFixture()
            defer { fixture.cleanUp() }
            let view = MarketingFrame(headline: frame.headline, detail: frame.detail, ui: try frame.ui(fixture))
            let shot = try await Snapshotter.render(view, appearance: .darkAqua)
            try #require(shot.size == appStoreCanvas, "\(frame.id) rendered at \(shot.size)")
            try shot.png.write(to: directory.appendingPathComponent("\(index + 1)-\(frame.id).png"))
        }
    }
}

// MARK: - Frames

extension AppStoreScreenshots {
    /// Twelve minutes and thirty-four seconds into a call.
    private static var midCall: Date { Date().addingTimeInterval(-754) }

    static let frames: [Frame] = [
        Frame(id: "record", headline: "Every call,\nwritten down.",
              detail: "Records Slack huddles, Teams calls and Google Meet from the menu bar, both sides, and transcribes them on your Mac.") { f in
            try f.addHistory()
            f.recorder.stageForScreenshots(.recording(since: midCall), lastSource: .slack)
            f.recorder.levels.stageForScreenshots(mic: 0.62, system: 0.45)
            return AnyView(MenuBarScene(status: .recording) { menu(f) })
        },
        Frame(id: "consent", headline: "Nothing records\nuntil you say so.",
              detail: "When a call starts you get a prompt, not a recording. It says who is recorded and where everything goes.") { _ in
            let prompt = ConfirmationController()
            prompt.stageForScreenshots(source: .slack, countdown: 12, cloudActive: false)
            return AnyView(AppWindow(scale: 1.6) { ConfirmationView(controller: prompt) })
        },
        Frame(id: "speakers", headline: "Know who\nsaid what.",
              detail: "After the call, name each voice. Names spotted in the call window are a click away.") { _ in
            AnyView(AppWindow(scale: 1.25) {
                ParticipantReviewView(request: RosterReview(
                    voices: [
                        VoiceCandidate(label: "Me", suggestion: "Me", sample: "Shall we get started?"),
                        VoiceCandidate(label: "Speaker 1", suggestion: "Priya Shah", sample: "Can we move the launch to Thursday?"),
                        VoiceCandidate(label: "Speaker 2", suggestion: "", sample: "Thursday works if design signs off today.")
                    ],
                    others: ["Marcus Lee", "Dana Wu"],
                    context: "Slack Huddle · 3 Nov at 09:21 · 25 min"),
                    accessibilityTrusted: true, onDone: { _ in }, onDelete: {})
            })
        },
        Frame(id: "notes", headline: "A note in\nyour vault.",
              detail: "Summary, action items and a speaker-labelled transcript, saved as markdown to any folder or Obsidian vault.") { _ in
            AnyView(NoteWindow(name: MarkdownWriter.fileName(SampleNote.metadata) + ".md", markdown: SampleNote.markdown))
        },
        Frame(id: "room", headline: "In-person\nmeetings, too.",
              detail: "Record the room from the microphone alone. Every voice is told apart, ready to name.") { f in
            f.recorder.stageForScreenshots(.recording(since: midCall), lastSource: .inPerson)
            f.recorder.levels.stageForScreenshots(mic: 0.5, system: 0, tracksSystemAudio: false)
            return AnyView(ZStack(alignment: .bottomLeading) {
                MenuBarScene(status: .recording) { menu(f) }
                AppWindow(scale: 1) {
                    ParticipantReviewView(request: RosterReview(
                        voices: [
                            VoiceCandidate(label: "Speaker 1", suggestion: "Dana Wu", sample: "Okay, quick round of updates."),
                            VoiceCandidate(label: "Speaker 2", suggestion: "Sam Ortiz", sample: "The migration finished overnight."),
                            VoiceCandidate(label: "Speaker 3", suggestion: "", sample: "I still need a reviewer for the API change.")
                        ],
                        others: [],
                        context: "In Person · 3 Nov at 10:02 · 48 min"),
                        accessibilityTrusted: true, onDone: { _ in }, onDelete: {})
                }
                .padding(.bottom, 40)
            })
        },
        Frame(id: "private", headline: "Your audio stays\non your Mac.",
              detail: "Transcription runs on-device. Cloud summaries are optional, and only ever send the transcript text.") { f in
            AnyView(AppWindow(scale: 1.15) {
                OnboardingView(permissions: f.permissions, settings: f.settings, startingAt: .welcome,
                               onClose: {}, onRelaunch: {})
            })
        }
    ]

    private static func menu(_ f: ScreenshotFixture) -> some View {
        MenuContent(recorder: f.recorder, settings: f.settings, permissions: f.permissions,
                    history: f.history, levels: f.recorder.levels)
    }
}

/// A believable note for the "notes" frame, rendered by the app's own writer.
@MainActor
private enum SampleNote {
    static let metadata = NoteMetadata(
        date: ScreenshotFixture.morning.addingTimeInterval(-20 * 60),
        source: .slack, duration: 25 * 60,
        participants: ["Me", "Priya Shah", "Marcus Lee"],
        topic: "Launch date and design sign-off")

    static let summary = """
        Moved the launch to Thursday, pending design sign-off today.

        **Action items**
        - Priya: confirm the Thursday slot with marketing
        - Marcus: send the final mocks for sign-off by 3pm
        - Me: update the release checklist
        """

    static let lines: [(Double, Speaker, String)] = [
        (4, .me, "Shall we get started? Main thing today is the launch date."),
        (11, Speaker(label: "Priya Shah"), "Can we move the launch to Thursday? Marketing needs two more days."),
        (19, Speaker(label: "Marcus Lee"), "Thursday works if design signs off today."),
        (26, .me, "Then let's aim for sign-off by three."),
        (31, Speaker(label: "Marcus Lee"), "I'll send the final mocks right after this.")
    ]

    static var markdown: String {
        let segments = lines.map { TranscriptSegment(start: $0.0, end: $0.0 + 6, text: $0.2, speaker: $0.1) }
        return MarkdownWriter.render(segments: segments, metadata: metadata, summary: summary)
    }
}

// MARK: - Composition

/// 1440 x 900 points: 2880 x 1800 pixels at 2x, an App Store size for Mac apps.
private let appStoreCanvas = CGSize(width: 1440, height: 900)

/// The App Store canvas: headline on the left, the app on the right, on true black.
private struct MarketingFrame<UI: View>: View {
    let headline: String
    let detail: String
    let ui: UI

    var body: some View {
        HStack(spacing: 48) {
            VStack(alignment: .leading, spacing: 24) {
                Text(headline)
                    .font(.system(size: 64, weight: .bold))
                    .tracking(-1.2)
                    .lineSpacing(2)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 24))
                    .lineSpacing(5)
                    .foregroundStyle(Color(white: 0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 540, alignment: .leading)

            ui.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 96)
        .frame(width: appStoreCanvas.width, height: appStoreCanvas.height)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}

/// A top-of-screen menu bar with the app's icon, and its menu hanging beneath it, as
/// the app actually appears.
private struct MenuBarScene<Menu: View>: View {
    let status: MenuBarIcon.Status
    @ViewBuilder let menu: Menu

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 18) {
                Image(nsImage: MenuBarIcon.image(status))
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
                Image(systemName: "magnifyingglass")
                Text("Tue 3 Nov  9:41").monospacedDigit()
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(Color(white: 0.11), in: Capsule())

            menu
                .background(Color(nsColor: .windowBackgroundColor))
                .chrome(cornerRadius: 12)
                .scaleEffect(1.3, anchor: .topTrailing)
                // Hangs centred under the app's icon, the first item in the bar.
                .padding(.trailing, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 40)
    }
}

/// One of the app's windows or panels, enlarged and given its window edge.
private struct AppWindow<Content: View>: View {
    let scale: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(Color(nsColor: .windowBackgroundColor))
            .chrome(cornerRadius: 12)
            .scaleEffect(scale)
    }
}

/// The saved note as a markdown document window, the way it lands in the vault.
private struct NoteWindow: View {
    let name: String
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                         Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) { Circle().fill($0).frame(width: 12, height: 12) }
                Spacer()
                Label(name, systemImage: "doc.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            Divider()
            Text(markdown)
                .font(.system(size: 12.5, design: .monospaced))
                .lineSpacing(3)
                .foregroundStyle(.primary)
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 620)
        .background(Color(nsColor: .textBackgroundColor))
        .chrome(cornerRadius: 12)
    }
}

private extension View {
    /// A window's rounded edge and hairline, which on black stands in for its shadow.
    func chrome(cornerRadius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16)))
    }
}
