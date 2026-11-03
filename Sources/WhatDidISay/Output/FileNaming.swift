import Foundation

enum FileNaming {
    /// `base.ext` in `folder`, or `base (2).ext`, `base (3).ext`, … until the name is free.
    static func uniqueURL(base: String, ext: String, in folder: URL) -> URL {
        var suffix = 1
        while true {
            let name = suffix == 1 ? base : "\(base) (\(suffix))"
            let candidate = folder.appendingPathComponent("\(name).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            suffix += 1
        }
    }
}

extension DateFormatter {
    /// Fixed-locale formatter, so file names and front matter don't change with the user's region.
    static func posix(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = pattern
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }
}
