import AppKit

/// Words and symbols shared by every surface, so the menu, panel, prompt and review
/// dialog name things the same way.

extension NotePipeline.Stage {
    var title: String {
        switch self {
        case .transcribing: "Transcribing"
        case .identifyingSpeakers: "Identifying speakers"
        case .summarizing: "Summarizing"
        case .reviewing: "Waiting for names"
        case .saving: "Saving note"
        }
    }
}

extension RecordingSource {
    /// What is being recorded, in a phrase: "Slack Huddle", "Call", "In Person".
    var recordingName: String {
        self == .manual ? "Call" : displayName
    }

    var symbolName: String {
        switch self {
        case .inPerson: "person.2.fill"
        case .googleMeet: "video.fill"
        case .manual, .slack, .teams: "phone.fill"
        }
    }
}

/// Speaks status changes that happen outside the popover (a call prompt, a capture
/// problem, a saved note), which VoiceOver users would otherwise never hear about.
@MainActor
enum Announcer {
    static func post(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue
        ])
    }
}
