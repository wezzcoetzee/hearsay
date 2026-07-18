import Foundation

/// Copies a finished call's audio files into the user-chosen audio folder,
/// named to match the note ("2026-07-18 0930 Slack Huddle system.m4a").
enum AudioArchiver {
    static func archive(_ session: RecordingSession, to folder: URL) throws {
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let base = "\(MarkdownWriter.fileTimestamp(session.startedAt)) \(session.source.displayName)"
        let tracks = [("system", session.systemAudioURL), ("mic", session.micAudioURL)]
        for (track, source) in tracks where fm.fileExists(atPath: source.path) {
            let destination = uniqueURL(base: "\(base) \(track)",
                                        ext: source.pathExtension,
                                        in: folder)
            try fm.copyItem(at: source, to: destination)
        }
    }

    private static func uniqueURL(base: String, ext: String, in folder: URL) -> URL {
        let candidate = folder.appendingPathComponent("\(base).\(ext)")
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        var suffix = 2
        while true {
            let next = folder.appendingPathComponent("\(base) (\(suffix)).\(ext)")
            if !FileManager.default.fileExists(atPath: next.path) { return next }
            suffix += 1
        }
    }
}
