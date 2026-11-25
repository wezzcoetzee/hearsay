import Foundation

/// Copies a finished call's audio files into the user-chosen audio folder,
/// named per the user's filename format setting.
enum AudioArchiver {
    static func archive(_ session: RecordingSession, to folder: URL, format: String) throws {
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let candidates: [(String, URL?)] = [("system", session.systemAudioURL), ("mic", session.micAudioURL)]
        let tracks = candidates.compactMap { track, url in url.map { (track, $0) } }
        for (track, source) in tracks where fm.fileExists(atPath: source.path) {
            let name = AudioFilenameFormatter.render(
                format: format,
                date: session.startedAt,
                source: session.source,
                track: track)
            let destination = FileNaming.uniqueURL(base: name, ext: source.pathExtension, in: folder)
            try fm.copyItem(at: source, to: destination)
        }
    }
}
