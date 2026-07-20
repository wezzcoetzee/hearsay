import Foundation

enum AudioFilenameFormatter {
    static func render(format: String, date: Date, source: RecordingSource, track: String) -> String {
        let substituted = format
            .replacingOccurrences(of: "{date}", with: formatted(date, "yyyy-MM-dd"))
            .replacingOccurrences(of: "{time}", with: formatted(date, "HHmm"))
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

    private static func formatted(_ date: Date, _ pattern: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = pattern
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }
}
