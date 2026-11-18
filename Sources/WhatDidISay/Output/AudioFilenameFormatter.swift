import Foundation

enum AudioFilenameFormatter {
    static func render(format: String, date: Date, source: RecordingSource, track: String) -> String {
        let substituted = format
            .replacingOccurrences(of: "{date}", with: DateFormatter.posix("yyyy-MM-dd").string(from: date))
            .replacingOccurrences(of: "{time}", with: DateFormatter.posix("HHmm").string(from: date))
            .replacingOccurrences(of: "{source}", with: source.displayName)
            .replacingOccurrences(of: "{track}", with: track)

        let cleaned = sanitize(substituted).trimmingCharacters(in: .whitespaces)

        guard cleaned.isEmpty || !format.contains("{track}") else { return cleaned }
        return cleaned.isEmpty ? track : "\(cleaned) \(track)"
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ":", with: "")
    }
}
