import Foundation
import WhisperKit

protocol Transcribing: Sendable {
    func transcribe(url: URL, speaker: Speaker, model: String) async throws -> [TranscriptSegment]
}

final class TranscriptionService: Transcribing, @unchecked Sendable {
    private var pipe: WhisperKit?
    private var loadedModel: String?

    func loadIfNeeded(model: String) async throws {
        if pipe != nil, loadedModel == model { return }
        pipe = try await WhisperKit(WhisperKitConfig(model: model, verbose: false, logLevel: .error))
        loadedModel = model
    }

    func transcribe(url: URL, speaker: Speaker, model: String) async throws -> [TranscriptSegment] {
        try await loadIfNeeded(model: model)
        guard let pipe else { return [] }

        let results = try await pipe.transcribe(audioPath: url.path)
        return results.flatMap { result in
            result.segments.compactMap { segment -> TranscriptSegment? in
                let text = Self.stripSpecialTokens(segment.text)
                guard !text.isEmpty else { return nil }
                return TranscriptSegment(
                    start: Double(segment.start),
                    end: Double(segment.end),
                    text: text,
                    speaker: speaker
                )
            }
        }
    }

    private static let specialTokenPattern = try! NSRegularExpression(pattern: "<\\|[^|]*\\|>")

    private static func stripSpecialTokens(_ raw: String) -> String {
        let range = NSRange(raw.startIndex..., in: raw)
        let stripped = specialTokenPattern.stringByReplacingMatches(in: raw, range: range, withTemplate: " ")
        return stripped
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
