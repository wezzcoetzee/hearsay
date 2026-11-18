import Foundation

enum MarkdownWriterError: Error {
    case encodingFailed
}

struct NoteMetadata {
    let date: Date
    let source: RecordingSource
    let duration: TimeInterval
    let participants: [String]
    /// What the call was about, from the summary. Nil when summaries are off or failed.
    var topic: String? = nil
}

enum MarkdownWriter {
    static func render(segments: [TranscriptSegment], metadata: NoteMetadata, summary: String?) -> String {
        var out = frontMatter(metadata)
        out += "\n# \(metadata.topic ?? metadata.source.displayName) — \(titleTimestamp(metadata.date))\n"

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

    static func write(_ contents: String, metadata: NoteMetadata, to folder: URL) throws -> URL {
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }

        guard let data = contents.data(using: .utf8) else {
            throw MarkdownWriterError.encodingFailed
        }
        let url = FileNaming.uniqueURL(base: fileName(metadata), ext: "md", in: folder)
        // A note created since the name was chosen is an error, never an overwrite.
        try data.write(to: url, options: .withoutOverwriting)
        return url
    }

    /// `2026-11-03 1430 Slack Huddle - Weekly goals review`, or without the topic when
    /// there isn't one. Characters a filename can't hold are dropped from the topic.
    static func fileName(_ metadata: NoteMetadata) -> String {
        let base = "\(fileTimestamp(metadata.date)) \(metadata.source.displayName)"
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines).union(.controlCharacters)
        let topic = (metadata.topic ?? "")
            .components(separatedBy: unsafe).joined(separator: " ")
            .split(separator: " ").joined(separator: " ")
            .prefix(60)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))
        return topic.isEmpty ? base : "\(base) - \(topic)"
    }

    private static func frontMatter(_ m: NoteMetadata) -> String {
        let minutes = Int((m.duration / 60).rounded())
        let names = m.participants.isEmpty ? ["Me"] : m.participants
        let participants = names.map(yamlFlowScalar).joined(separator: ", ")
        let lines = [
            "---",
            "date: \(isoDate(m.date))",
            "source: \(yamlFlowScalar(m.source.displayName))",
            m.topic.map { "topic: \(yamlFlowScalar($0))" },
            "participants: [\(participants)]",
            "duration: \(minutes)m",
            "---"
        ]
        return lines.compactMap { $0 }.joined(separator: "\n") + "\n"
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
        DateFormatter.posix("yyyy-MM-dd").string(from: date)
    }

    private static func titleTimestamp(_ date: Date) -> String {
        DateFormatter.posix("yyyy-MM-dd HH:mm").string(from: date)
    }

    static func fileTimestamp(_ date: Date) -> String {
        DateFormatter.posix("yyyy-MM-dd HHmm").string(from: date)
    }
}
