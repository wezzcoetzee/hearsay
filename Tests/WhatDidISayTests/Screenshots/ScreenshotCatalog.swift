import AppKit
import Foundation
import SwiftUI
import Testing
@testable import WhatDidISay

/// Every surface of the app in the states a user meets, rendered light and dark into
/// `$SCREENSHOTS_DIR` with an `index.html` contact sheet. Skipped unless that variable
/// is set; run it with `Scripts/screenshots.sh`.
@MainActor
@Suite struct ScreenshotCatalog {
    nonisolated static let outputDirectory = ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    }

    struct Scene {
        let surface: String
        let id: String
        let caption: String
        var fixture: @MainActor () throws -> ScreenshotFixture = { try ScreenshotFixture() }
        /// For views taller than their window, such as Settings.
        var scrolledToBottom = false
        let view: @MainActor (ScreenshotFixture) throws -> AnyView
    }

    @Test(.enabled(if: outputDirectory != nil))
    func renderCatalog() async throws {
        let directory = try #require(Self.outputDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var rendered: [(scene: Scene, files: [String: Snapshotter.Shot])] = []
        for scene in Self.scenes {
            var files: [String: Snapshotter.Shot] = [:]
            for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                // A fresh fixture per render: scenes set up state as they build the view.
                let fixture = try scene.fixture()
                defer { fixture.cleanUp() }
                let shot = try await Snapshotter.render(try scene.view(fixture), appearance: appearance,
                                                        scrolledToBottom: scene.scrolledToBottom)
                let name = "\(scene.surface.slug)-\(scene.id)-\(mode).png"
                try shot.png.write(to: directory.appendingPathComponent(name))
                files[name] = shot
            }
            rendered.append((scene, files))
        }
        try ContactSheet.html(for: rendered.map { ($0.scene, $0.files) })
            .write(to: directory.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }
}

// MARK: - Scenes

extension ScreenshotCatalog {
    static let scenes: [Scene] = menuScenes + panelScenes + promptScenes + reviewScenes
        + onboardingScenes + settingsScenes

    private static func menu(_ f: ScreenshotFixture) -> AnyView {
        AnyView(MenuContent(recorder: f.recorder, settings: f.settings, permissions: f.permissions,
                            history: f.history, levels: f.recorder.levels))
    }

    /// Twelve minutes and thirty-four seconds into a call.
    private static var midCall: Date { Date().addingTimeInterval(-754) }

    static let menuScenes: [Scene] = [
        Scene(surface: "Menu", id: "first-run", caption: "First run, nothing granted yet",
              fixture: { try ScreenshotFixture(microphone: .unknown, screenRecording: .denied, vault: false) },
              view: { menu($0) }),
        Scene(surface: "Menu", id: "choose-folder", caption: "Permissions granted, no notes folder",
              fixture: { try ScreenshotFixture(vault: false) },
              view: { menu($0) }),
        Scene(surface: "Menu", id: "ready-empty", caption: "Ready, no recordings yet",
              view: { menu($0) }),
        Scene(surface: "Menu", id: "ready-history", caption: "Ready with recent recordings and auto-detect on") { f in
            try f.addHistory()
            f.settings.autoDetect = true
            return menu(f)
        },
        Scene(surface: "Menu", id: "recording-call", caption: "Recording a call, both tracks live") { f in
            try f.addHistory()
            f.recorder.stageForScreenshots(.recording(since: midCall), lastSource: .slack)
            f.recorder.levels.stageForScreenshots(mic: 0.62, system: 0.45)
            return menu(f)
        },
        Scene(surface: "Menu", id: "recording-room", caption: "Recording the room, microphone only") { f in
            f.recorder.stageForScreenshots(.recording(since: midCall), lastSource: .inPerson)
            f.recorder.levels.stageForScreenshots(mic: 0.48, system: 0, tracksSystemAudio: false)
            return menu(f)
        },
        Scene(surface: "Menu", id: "recording-mic-silent", caption: "Recording, but the microphone hears nothing") { f in
            f.recorder.stageForScreenshots(.recording(since: midCall), lastSource: .teams)
            f.recorder.levels.stageForScreenshots(mic: 0, system: 0.38, micSilent: true)
            return menu(f)
        },
        Scene(surface: "Menu", id: "recording-interrupted", caption: "Call audio stopped mid-call") { f in
            f.recorder.stageForScreenshots(.recording(since: midCall), lastSource: .slack,
                                           captureWarning: .callAudioStopped)
            f.recorder.levels.stageForScreenshots(mic: 0.55, system: 0)
            return menu(f)
        },
        Scene(surface: "Menu", id: "saving-audio", caption: "Stopped, closing the audio files") { f in
            f.recorder.stageForScreenshots(.finishing)
            return menu(f)
        },
        Scene(surface: "Menu", id: "transcribing", caption: "Transcribing on-device") { f in
            try f.addHistory()
            f.recorder.stageForScreenshots(.processing(.transcribing), lastSource: .googleMeet)
            return menu(f)
        },
        Scene(surface: "Menu", id: "reviewing", caption: "Waiting on the participant review") { f in
            f.recorder.stageForScreenshots(.processing(.reviewing), lastSource: .slack)
            return menu(f)
        },
        Scene(surface: "Menu", id: "summarizing-cloud", caption: "Summarizing with the cloud backend") { f in
            f.settings.summaryEnabled = true
            f.settings.summaryBackend = .cloud
            f.settings.anthropicAPIKey = "sk-ant-screenshot"
            f.recorder.stageForScreenshots(.processing(.summarizing), lastSource: .teams)
            return menu(f)
        },
        Scene(surface: "Menu", id: "saved", caption: "Note saved") { f in
            try f.addHistory()
            f.recorder.stageForScreenshots(.idle, lastSave: .init(noteURL: try f.noteURL(), folderName: "Notes", warning: nil))
            return menu(f)
        },
        Scene(surface: "Menu", id: "saved-with-warning", caption: "Note saved, but the audio couldn't be archived") { f in
            f.settings.keepAudio = true
            f.recorder.stageForScreenshots(.idle, lastSave: .init(
                noteURL: try f.noteURL(), folderName: "Notes",
                warning: "Couldn't copy the audio to Call Audio. It's kept in the app's Library folder."))
            return menu(f)
        },
        Scene(surface: "Menu", id: "no-screen-recording", caption: "Microphone only: the main button records in person",
              fixture: { try ScreenshotFixture(screenRecording: .denied) }) { menu($0) },
        Scene(surface: "Menu", id: "failed-to-start", caption: "Capture couldn't start") { f in
            f.recorder.stageForScreenshots(
                .failed("Couldn't start recording. Another app may be using the microphone or system audio."),
                failedToStart: true, lastSource: .slack)
            return menu(f)
        },
        Scene(surface: "Menu", id: "needs-attention-many", caption: "Five recordings waiting: three shown, Show All for the rest") { f in
            let pending = (0..<5).map { f.session(.slack, minutesAgo: 60 * (2 + $0), lasting: 10 + $0) }
            pending[0].setAsideReason = RecordingController.waitingForNames
            f.recorder.stageForScreenshots(.idle, needsAttention: pending)
            return menu(f)
        },
        Scene(surface: "Menu", id: "needs-attention", caption: "Recordings that never became notes") { f in
            let transcribed = f.session(.googleMeet, minutesAgo: 50, lasting: 31)
            try transcribed.saveTranscript([])
            let failed = f.session(.slack, minutesAgo: 60 * 3, lasting: 12)
            failed.setAsideReason = "failed while transcribing"
            let pending = [transcribed, failed, f.session(.inPerson, minutesAgo: 60 * 26, lasting: 48)]
            f.recorder.stageForScreenshots(.idle, needsAttention: pending)
            return menu(f)
        }
    ]

    private static func panel(_ f: ScreenshotFixture, source: RecordingSource = .slack,
                              collapsed: Bool = false, warning: CaptureIssue? = nil) -> AnyView {
        let controller = RecordingControlPanelController(levels: f.recorder.levels)
        controller.warning = warning
        controller.isEnabled = false  // keep the real NSPanel off screen
        controller.update(for: .recording(since: midCall), source: source)
        if collapsed { controller.toggleCollapsed() }
        return AnyView(RecordingControlPanelView(controller: controller))
    }

    static let panelScenes: [Scene] = [
        Scene(surface: "Floating panel", id: "call", caption: "Recording a call") { f in
            f.recorder.levels.stageForScreenshots(mic: 0.62, system: 0.45)
            return panel(f)
        },
        Scene(surface: "Floating panel", id: "room", caption: "Recording in person") { f in
            f.recorder.levels.stageForScreenshots(mic: 0.5, system: 0, tracksSystemAudio: false)
            return panel(f, source: .inPerson)
        },
        Scene(surface: "Floating panel", id: "mic-silent", caption: "No sound from the microphone") { f in
            f.recorder.levels.stageForScreenshots(mic: 0, system: 0.4, micSilent: true)
            return panel(f)
        },
        Scene(surface: "Floating panel", id: "interrupted", caption: "Call audio stopped mid-call") { f in
            f.recorder.levels.stageForScreenshots(mic: 0.55, system: 0)
            return panel(f, warning: .callAudioStopped)
        },
        Scene(surface: "Floating panel", id: "collapsed", caption: "Collapsed") { f in
            f.recorder.levels.stageForScreenshots(mic: 0.55, system: 0.3)
            return panel(f, collapsed: true)
        },
        Scene(surface: "Floating panel", id: "collapsed-issue", caption: "Collapsed, with the microphone silent") { f in
            f.recorder.levels.stageForScreenshots(mic: 0, system: 0.3, micSilent: true)
            return panel(f, collapsed: true)
        }
    ]

    private static func prompt(_ source: RecordingSource, countdown: Int, cloud: Bool) -> AnyView {
        let controller = ConfirmationController()
        controller.stageForScreenshots(source: source, countdown: countdown, cloudActive: cloud)
        return AnyView(ConfirmationView(controller: controller))
    }

    static let promptScenes: [Scene] = [
        Scene(surface: "Call prompt", id: "slack", caption: "Slack huddle detected") { _ in
            prompt(.slack, countdown: 15, cloud: false)
        },
        Scene(surface: "Call prompt", id: "meet", caption: "Google Meet detected") { _ in
            prompt(.googleMeet, countdown: 9, cloud: false)
        },
        Scene(surface: "Call prompt", id: "teams-cloud", caption: "Teams call detected, cloud summaries on") { _ in
            prompt(.teams, countdown: 4, cloud: true)
        },
        Scene(surface: "Call prompt", id: "busy", caption: "Call detected while the last recording waits for names") { _ in
            let controller = ConfirmationController()
            controller.stageForScreenshots(source: .slack, countdown: 12, cloudActive: false, blocker: .awaitingNames)
            return AnyView(ConfirmationView(controller: controller))
        },
        Scene(surface: "Call prompt", id: "start-failed", caption: "Start Recording was clicked but capture didn't start") { _ in
            let controller = ConfirmationController()
            controller.stageForScreenshots(source: .slack, countdown: 15, cloudActive: false, blocker:
                .startFailed("Couldn't start recording. Another app may be using the microphone or system audio."))
            return AnyView(ConfirmationView(controller: controller))
        }
    ]

    private static func review(_ voices: [VoiceCandidate], seen: [String] = [], trusted: Bool = true,
                               context: String = "Slack Huddle · 3 Nov at 09:21 · 25 min") -> AnyView {
        AnyView(ParticipantReviewView(request: RosterReview(voices: voices, others: seen, context: context),
                                      accessibilityTrusted: trusted, onDone: { _ in }, onDelete: {}))
    }

    static let reviewScenes: [Scene] = [
        Scene(surface: "Participant review", id: "call", caption: "After a call: two remote voices and names seen on screen") { _ in
            review([
                VoiceCandidate(label: "Me", suggestion: "Me", sample: "Shall we get started?"),
                VoiceCandidate(label: "Speaker 1", suggestion: "", sample: "Can we move the launch to Thursday?"),
                VoiceCandidate(label: "Speaker 2", suggestion: "", sample: "Thursday works if design signs off today.")
            ], seen: ["Priya Shah", "Marcus Lee"])
        },
        Scene(surface: "Participant review", id: "in-person", caption: "After recording the room: every voice diarized") { _ in
            review([
                VoiceCandidate(label: "Speaker 1", suggestion: "", sample: "Okay, quick round of updates."),
                VoiceCandidate(label: "Speaker 2", suggestion: "", sample: "The migration finished overnight."),
                VoiceCandidate(label: "Speaker 3", suggestion: "", sample: "I still need a reviewer for the API change, and someone to own the rollout plan once it lands.")
            ], context: "In Person · 2 Nov at 11:41 · 48 min")
        },
        Scene(surface: "Participant review", id: "accessibility-tip", caption: "Accessibility off, so name detection is limited") { _ in
            review([
                VoiceCandidate(label: "Me", suggestion: "Me", sample: "Thanks for joining."),
                VoiceCandidate(label: "Others", suggestion: "", sample: "Happy to, let's go through the numbers.")
            ], trusted: false)
        }
    ]

    /// Accessibility defaults to allowed, so a scene never depends on this Mac's setting.
    private static func onboarding(_ f: ScreenshotFixture, _ step: OnboardingView.Step,
                                   accessibilityTrusted: Bool = true) -> AnyView {
        AnyView(OnboardingView(permissions: f.permissions, settings: f.settings, startingAt: step,
                               accessibilityTrusted: accessibilityTrusted, onClose: {}, onRelaunch: {}))
    }

    private static let unset = { try ScreenshotFixture(microphone: .unknown, screenRecording: .denied, vault: false) }

    static let onboardingScenes: [Scene] = [
        Scene(surface: "Onboarding", id: "1-welcome", caption: "Welcome", fixture: unset) { onboarding($0, .welcome) },
        Scene(surface: "Onboarding", id: "2-microphone", caption: "Microphone, not yet asked", fixture: unset) {
            onboarding($0, .microphone)
        },
        Scene(surface: "Onboarding", id: "2-microphone-denied", caption: "Microphone refused earlier",
              fixture: { try ScreenshotFixture(microphone: .denied, screenRecording: .denied, vault: false) }) {
            onboarding($0, .microphone)
        },
        Scene(surface: "Onboarding", id: "2-microphone-granted", caption: "Microphone granted",
              fixture: { try ScreenshotFixture(screenRecording: .denied, vault: false) }) { onboarding($0, .microphone) },
        Scene(surface: "Onboarding", id: "3-screen-recording", caption: "Screen Recording, not yet asked",
              fixture: { try ScreenshotFixture(screenRecording: .denied, vault: false) }) { onboarding($0, .screenRecording) },
        Scene(surface: "Onboarding", id: "3-screen-recording-relaunch", caption: "Screen Recording asked for, waiting on a relaunch",
              fixture: { try ScreenshotFixture(screenRecording: .denied, vault: false) }) {
            $0.permissions.stageScreenRecordingRequested()
            return onboarding($0, .screenRecording)
        },
        Scene(surface: "Onboarding", id: "4-notes-folder", caption: "Notes folder, not chosen",
              fixture: { try ScreenshotFixture(vault: false) }) { onboarding($0, .notesFolder) },
        Scene(surface: "Onboarding", id: "4-notes-folder-set", caption: "Notes folder chosen") { onboarding($0, .notesFolder) },
        Scene(surface: "Onboarding", id: "5-done", caption: "All set") { onboarding($0, .done) },
        Scene(surface: "Onboarding", id: "5-done-auto-detect", caption: "Auto-detect on, Accessibility not allowed") {
            $0.settings.autoDetect = true
            return onboarding($0, .done, accessibilityTrusted: false)
        },
        Scene(surface: "Onboarding", id: "5-done-in-person", caption: "Finished having skipped Screen Recording",
              fixture: { try ScreenshotFixture(screenRecording: .denied) }) { onboarding($0, .done) }
    ]

    static let settingsScenes: [Scene] = [
        Scene(surface: "Settings", id: "screen-recording-pending", caption: "Screen Recording asked for, waiting on a relaunch",
              fixture: { try ScreenshotFixture(screenRecording: .denied) }) { f in
            f.permissions.stageScreenRecordingRequested()
            return AnyView(SettingsView(settings: f.settings, permissions: f.permissions, recorder: f.recorder))
        },
        Scene(surface: "Settings", id: "default", caption: "Defaults") { f in
            AnyView(SettingsView(settings: f.settings, permissions: f.permissions, recorder: f.recorder))
        },
        Scene(surface: "Settings", id: "local-summary", caption: "Local summaries through Ollama, keeping audio",
              scrolledToBottom: true) { f in
            f.settings.summaryEnabled = true
            f.settings.keepAudio = true
            f.settings.useAudioFolder(try f.folder("Call Audio"))
            return AnyView(SettingsView(settings: f.settings, permissions: f.permissions, recorder: f.recorder))
        },
        Scene(surface: "Settings", id: "cloud-summary", caption: "Cloud summaries through Anthropic",
              scrolledToBottom: true) { f in
            f.settings.summaryEnabled = true
            f.settings.summaryBackend = .cloud
            f.settings.anthropicAPIKey = "sk-ant-screenshot"
            f.settings.hasAcknowledgedCloud = true
            f.settings.diarize = true
            return AnyView(SettingsView(settings: f.settings, permissions: f.permissions, recorder: f.recorder))
        }
    ]
}

// MARK: - Contact sheet

private enum ContactSheet {
    static func html(for scenes: [(ScreenshotCatalog.Scene, [String: Snapshotter.Shot])]) -> String {
        var surfaces: [String] = []
        for (scene, _) in scenes where !surfaces.contains(scene.surface) { surfaces.append(scene.surface) }

        let sections = surfaces.map { surface in
            let rows = scenes.filter { $0.0.surface == surface }.map { scene, shots in
                let images = shots.keys.sorted { $0.hasSuffix("light.png") && !$1.hasSuffix("light.png") }
                    .map { name -> String in
                        let size = shots[name]!.size
                        return #"<a href="\#(name)"><img src="\#(name)" width="\#(Int(size.width))" height="\#(Int(size.height))" alt="\#(escape(scene.caption))"></a>"#
                    }
                    .joined()
                return #"<figure><figcaption>\#(escape(scene.caption)) <code>\#(scene.id)</code></figcaption><div>\#(images)</div></figure>"#
            }
            return #"<section id="\#(surface.slug)"><h2>\#(escape(surface))</h2>\#(rows.joined())</section>"#
        }
        let nav = surfaces.map { ##"<a href="#\##($0.slug)">\##(escape($0))</a>"## }.joined()
        let count = scenes.reduce(0) { $0 + $1.1.count }

        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <title>What Did I Say · screenshots</title>
        <style>
        body{margin:0;background:#000;color:#fff;font:13px/1.4 -apple-system,system-ui,sans-serif}
        header{position:sticky;top:0;background:#000;padding:12px 20px;border-bottom:1px solid #222;display:flex;gap:16px;align-items:baseline;flex-wrap:wrap;z-index:1}
        header h1{font-size:15px;margin:0}
        header span{color:#888}
        nav a{color:#fff;margin-right:12px;text-decoration:none;border-bottom:1px solid #444}
        section{padding:16px 20px 4px}
        h2{font-size:14px;margin:0 0 10px}
        figure{margin:0 0 18px}
        figcaption{margin-bottom:6px}
        code{color:#888;font:11px ui-monospace,monospace;margin-left:6px}
        figure div{display:flex;gap:12px;align-items:flex-start;flex-wrap:wrap}
        img{display:block;border:1px solid #222}
        </style></head><body>
        <header><h1>What Did I Say</h1><span>\(count) screenshots, light and dark</span><nav>\(nav)</nav></header>
        \(sections.joined(separator: "\n"))
        </body></html>
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private extension String {
    var slug: String {
        lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
    }
}
