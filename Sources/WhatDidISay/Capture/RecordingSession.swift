import Foundation

enum RecordingSource: String {
    case manual
    case inPerson
    case slack
    case teams
    case googleMeet

    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .inPerson: return "In Person"
        case .slack: return "Slack Huddle"
        case .teams: return "Teams Call"
        case .googleMeet: return "Google Meet"
        }
    }

    var bundleIDs: [String] {
        switch self {
        case .manual, .inPerson: return []
        case .slack: return ["com.tinyspeck.slackmacgap"]
        case .teams: return ["com.microsoft.teams2", "com.microsoft.teams"]
        case .googleMeet: return RecordingSource.browserBundleIDs
        }
    }

    /// Chromium and WebKit browsers that can host a Google Meet call, in preference order.
    static let browserBundleIDs = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi",
        "org.mozilla.firefox",
        "com.apple.Safari"
    ]

    /// In-person meetings are recorded from the microphone alone: everyone is in the
    /// room, so there is no far-end audio to capture and no reason to ask for Screen
    /// Recording.
    var usesSystemAudio: Bool { self != .inPerson }

    /// Apps recognised by their own bundle id when the mic goes live. Browser calls
    /// aren't here: a running browser isn't a call, so they need the tab check in
    /// `BrowserCallDetector` instead.
    static let detectable: [RecordingSource] = [.slack, .teams]

    static func source(forBundleID bundleID: String) -> RecordingSource? {
        detectable.first { $0.bundleIDs.contains(bundleID) }
    }
}

final class RecordingSession {
    let id: UUID
    let source: RecordingSource
    let startedAt: Date
    var finishedAt: Date?
    var noteURL: URL?
    var segmentCount: Int = 0
    var participants: [String] = []
    /// Names spotted on screen during the call, kept with the session so a retry
    /// after a failure still has them.
    var detectedParticipants: [String] = []

    let directory: URL

    init(source: RecordingSource) {
        self.id = UUID()
        self.source = source
        self.startedAt = Date()

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhatDidISay/Recordings", isDirectory: true)
        self.directory = base.appendingPathComponent(Self.folderName(for: startedAt, id: id), isDirectory: true)
    }

    /// `nil` for sources recorded from the microphone alone, so callers can't reach
    /// for a system track that was never captured.
    var systemAudioURL: URL? {
        source.usesSystemAudio ? directory.appendingPathComponent("system.m4a") : nil
    }

    var micAudioURL: URL { directory.appendingPathComponent("mic.caf") }

    var duration: TimeInterval {
        (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func deleteRecording() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func folderName(for date: Date, id: UUID) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return "\(fmt.string(from: date))_\(id.uuidString.prefix(8))"
    }
}
