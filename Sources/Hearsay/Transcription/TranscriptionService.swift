import Foundation
import WhisperKit

protocol Transcribing: Sendable {
    func transcribe(url: URL, speaker: Speaker, model: String, hints: [String]) async throws -> [TranscriptSegment]
}

final class TranscriptionService: Transcribing, @unchecked Sendable {
    private var pipe: WhisperKit?
    private var loadedModel: String?

    func loadIfNeeded(model: String) async throws {
        if pipe != nil, loadedModel == model { return }
        // `load` must be explicit. WhisperKit only loads eagerly when given a model folder;
        // otherwise each VAD chunk of a long recording calls `loadModels()` concurrently
        // on first transcribe, races on the Core ML models, and segfaults.
        pipe = try await WhisperKit(WhisperKitConfig(model: model, verbose: false, logLevel: .error, load: true))
        loadedModel = model
    }

    func transcribe(url: URL, speaker: Speaker, model: String, hints: [String]) async throws -> [TranscriptSegment] {
        // The system writer only creates its file once audio arrives, so a call where
        // the far end never made a sound has no track. That's silence, not a failure.
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        try await loadIfNeeded(model: model)
        guard let pipe else { return [] }

        let options = Self.decodeOptions(promptTokens: promptTokens(for: hints, pipe: pipe))
        let results = try await pipe.transcribe(audioPath: url.path, decodeOptions: options)
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

    private func promptTokens(for hints: [String], pipe: WhisperKit) -> [Int]? {
        guard !hints.isEmpty, let tokenizer = pipe.tokenizer else { return nil }
        let phrase = " Participants: " + hints.joined(separator: ", ") + "."
        let tokens = tokenizer.encode(text: phrase)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return tokens.isEmpty ? nil : tokens
    }

    private static func decodeOptions(promptTokens: [Int]?) -> DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: "en",
            temperatureFallbackCount: 5,
            usePrefillPrompt: true,
            usePrefillCache: promptTokens == nil,
            wordTimestamps: false,
            promptTokens: promptTokens,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.6,
            chunkingStrategy: .vad
        )
    }

    private static let specialTokenPattern = try! NSRegularExpression(pattern: "<\\|[^|]*\\|>")

    private static func stripSpecialTokens(_ raw: String) -> String {
        let range = NSRange(raw.startIndex..., in: raw)
        let stripped = specialTokenPattern.stringByReplacingMatches(in: raw, range: range, withTemplate: " ")
        return
            stripped
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
