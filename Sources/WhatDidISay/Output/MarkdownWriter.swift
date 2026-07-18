import Foundation

enum MarkdownWriterError: Error {
    case encodingFailed
}

struct NoteMetadata {
    let date: Date
    let source: RecordingSource
    let duration: TimeInterval
    let participants: [String]
}

enum MarkdownWriter {
    static func render(segments: [TranscriptSegment], metadata: NoteMetadata, summary: String?) -> String {
        var out = frontMatter(metadata)
        out += "\n# \(metadata.source.displayName) — \(titleTimestamp(metadata.date))\n"

        if let summary, !summary.isEmpty {
            out += "\n## Summary\n\(summary)\n"
        }

        out += "\n## Transcript\n"
        if segments.isEmpty {
            out += "_No speech detected._\n"
        } else {
            for seg in segments {
                out += "**[\(seg.timestamp)] \(seg.speaker.label):** \(seg.text)\n"
            }
        }
        return out
    }

    static func write(_ contents: String, source: RecordingSource, date: Date, to folder: URL) throws -> URL {
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }

        guard let data = contents.data(using: .utf8) else {
            throw MarkdownWriterError.encodingFailed
        }
        let url = uniqueURL(base: "\(fileTimestamp(date)) \(source.displayName)", in: folder)
        try data.write(to: url)
        return url
    }

    private static func uniqueURL(base: String, in folder: URL) -> URL {
        let candidate = folder.appendingPathComponent("\(base).md")
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        var suffix = 2
        while true {
            let next = folder.appendingPathComponent("\(base) (\(suffix)).md")
            if !FileManager.default.fileExists(atPath: next.path) { return next }
            suffix += 1
        }
    }

    private static func frontMatter(_ m: NoteMetadata) -> String {
        let minutes = Int((m.duration / 60).rounded())
        let names = m.participants.isEmpty ? ["Me"] : m.participants
        let participants = names.map(yamlFlowScalar).joined(separator: ", ")
        return """
        ---
        date: \(isoDate(m.date))
        source: \(yamlFlowScalar(m.source.displayName))
        participants: [\(participants)]
        duration: \(minutes)m
        ---
        """ + "\n"
    }

    private static func yamlFlowScalar(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private static func isoDate(_ date: Date) -> String {
        format(date, "yyyy-MM-dd")
    }

    private static func titleTimestamp(_ date: Date) -> String {
        format(date, "yyyy-MM-dd HH:mm")
    }

    static func fileTimestamp(_ date: Date) -> String {
        format(date, "yyyy-MM-dd HHmm")
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = pattern
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }
}
