import Foundation

/// Collects participant names seen across repeated on-screen samples during a call
/// and keeps only those that recur, so a single bad OCR or accessibility read does
/// not permanently pollute the roster.
struct ParticipantAccumulator {
    private var counts: [String: Int] = [:]
    private(set) var sampleCount = 0

    mutating func record(_ names: Set<String>) {
        sampleCount += 1
        for name in names { counts[name, default: 0] += 1 }
    }

    func resolved() -> [String] {
        guard sampleCount > 2 else { return Array(counts.keys) }
        return counts.filter { $0.value >= 2 }.map(\.key)
    }
}
