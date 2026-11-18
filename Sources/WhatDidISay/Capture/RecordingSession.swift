import Foundation

enum RecordingSource: String, Codable {
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
        "com.apple.Safari",
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
    /// How far a recording has got toward becoming a note. Written beside the audio at
    /// every step, so a crash or a quit can't make the app forget a call: anything short
    /// of `.noted` is picked up again on the next launch.
    enum Progress: String, Codable {
        case recording
        case recorded
        case transcribed
        case noted
    }

    static let recordingsFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("WhatDidISay/Recordings", isDirectory: true)

    let id: UUID
    let source: RecordingSource
    let startedAt: Date
    var finishedAt: Date?
    private(set) var progress: Progress
    var noteURL: URL?
    var segmentCount: Int = 0
    var participants: [String] = []
    /// Names spotted on screen during the call, kept with the session so a retry
    /// after a failure still has them.
    var detectedParticipants: [String] = []
    /// Why this recording is waiting under Needs Attention, e.g. "failed while
    /// transcribing", shown on its row. Only known for this launch; a recording
    /// recovered after a relaunch says how far it got instead.
    var setAsideReason: String?
    /// Why the saved note has no summary, when summaries are on but one couldn't be made.
    var summaryFailure: String?

    let directory: URL

    convenience init(source: RecordingSource, startedAt: Date = Date(), in folder: URL = recordingsFolder) {
        let id = UUID()
        self.init(
            id: id, source: source, startedAt: startedAt, progress: .recording,
            directory: folder.appendingPathComponent(Self.folderName(for: startedAt, id: id), isDirectory: true))
    }

    private init(id: UUID, source: RecordingSource, startedAt: Date, progress: Progress, directory: URL) {
        self.id = id
        self.source = source
        self.startedAt = startedAt
        self.progress = progress
        self.directory = directory
    }

    /// `nil` for sources recorded from the microphone alone, so callers can't reach
    /// for a system track that was never captured.
    var systemAudioURL: URL? {
        source.usesSystemAudio ? directory.appendingPathComponent("system.m4a") : nil
    }

    var micAudioURL: URL { Self.micAudioURL(in: directory) }

    private var manifestURL: URL { Self.manifestURL(in: directory) }
    private var transcriptURL: URL { directory.appendingPathComponent("transcript.json") }

    var duration: TimeInterval {
        (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func deleteRecording() {
        try? FileManager.default.removeItem(at: directory)
    }

    func advance(to progress: Progress) throws {
        self.progress = progress
        try prepareDirectory()
        let manifest = Manifest(
            id: id, source: source, startedAt: startedAt, finishedAt: finishedAt,
            progress: progress, detectedParticipants: detectedParticipants)
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
    }

    func saveTranscript(_ segments: [TranscriptSegment]) throws {
        try prepareDirectory()
        try JSONEncoder().encode(segments).write(to: transcriptURL, options: .atomic)
        try advance(to: .transcribed)
    }

    /// The transcript an earlier run already paid for, so a retry goes straight to review.
    var savedTranscript: [TranscriptSegment]? {
        guard progress == .transcribed, let data = try? Data(contentsOf: transcriptURL) else { return nil }
        return try? JSONDecoder().decode([TranscriptSegment].self, from: data)
    }

    /// Every recording in `folder` that never became a note, newest first. Folders
    /// from before progress was tracked have no manifest, so they're rebuilt from
    /// their name and audio unless `notedPaths` (from history) says they were saved.
    static func unfinished(in folder: URL = recordingsFolder, notedPaths: Set<String> = []) -> [RecordingSession] {
        let folders =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        let noted = Set(notedPaths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path })
        return
            folders
            .filter { !noted.contains($0.resolvingSymlinksInPath().path) }
            .compactMap(recover)
            .filter { $0.progress != .noted }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private static func recover(_ directory: URL) -> RecordingSession? {
        // Without the mic track there's nothing to transcribe.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: micAudioURL(in: directory).path)
        else { return nil }

        let session: RecordingSession
        if let data = try? Data(contentsOf: manifestURL(in: directory)),
            let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        {
            session = RecordingSession(
                id: manifest.id, source: manifest.source, startedAt: manifest.startedAt,
                progress: manifest.progress, directory: directory)
            session.finishedAt = manifest.finishedAt
            session.detectedParticipants = manifest.detectedParticipants
        } else if let startedAt = folderDateFormatter().date(from: String(directory.lastPathComponent.prefix(19))) {
            // Older recordings didn't note their source. Every one of them was a call.
            session = RecordingSession(
                id: UUID(), source: .manual, startedAt: startedAt,
                progress: .recorded, directory: directory)
        } else {
            return nil
        }
        // A crash mid-call never recorded an end; the mic track's last write is when it stopped.
        if session.finishedAt == nil {
            session.finishedAt = attributes[.modificationDate] as? Date
        }
        return session
    }

    private struct Manifest: Codable {
        let id: UUID
        let source: RecordingSource
        let startedAt: Date
        let finishedAt: Date?
        let progress: Progress
        let detectedParticipants: [String]
    }

    private static func micAudioURL(in directory: URL) -> URL { directory.appendingPathComponent("mic.caf") }
    private static func manifestURL(in directory: URL) -> URL { directory.appendingPathComponent("session.json") }

    private static func folderName(for date: Date, id: UUID) -> String {
        "\(folderDateFormatter().string(from: date))_\(id.uuidString.prefix(8))"
    }

    private static func folderDateFormatter() -> DateFormatter {
        .posix("yyyy-MM-dd_HH-mm-ss")
    }
}
