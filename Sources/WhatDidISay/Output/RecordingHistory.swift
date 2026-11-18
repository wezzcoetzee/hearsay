import Combine
import Foundation

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let source: String
    let notePath: String?
    let recordingPath: String?
    let segmentCount: Int
    /// Missing from entries written before durations were kept.
    let duration: TimeInterval?
    /// Who was named in review, so calls from the same app can be told apart. Missing
    /// from older entries.
    let participants: [String]?

    var noteURL: URL? { notePath.map { URL(fileURLWithPath: $0) } }
}

@MainActor
final class RecordingHistory: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL
    private let maxEntries = 20

    static let defaultFileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("WhatDidISay/history.json")

    init(fileURL: URL = RecordingHistory.defaultFileURL) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        load()
    }

    func add(_ session: RecordingSession) {
        let entry = HistoryEntry(
            id: session.id,
            date: session.startedAt,
            source: session.source.recordingName,
            notePath: session.noteURL?.path,
            recordingPath: session.directory.path,
            segmentCount: session.segmentCount,
            duration: session.duration,
            participants: session.participants.filter { $0 != Speaker.me.label }
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        save()
    }

    // History is only a list. Removing an entry never deletes files: by the time a
    // call is listed its audio is gone, unless archiving failed, and then it's audio
    // the user asked to keep.
    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            entries = try JSONDecoder.iso.decode([HistoryEntry].self, from: data)
        } catch {
            // Starting empty would let the next save overwrite whatever this file held.
            NSLog("History is unreadable, moving it aside: \(error)")
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = fileURL.deletingLastPathComponent().appendingPathComponent("history.corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
        }
    }

    private func save() {
        do {
            try JSONEncoder.iso.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Couldn't save history: \(error)")
        }
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
