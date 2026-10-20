import Foundation

protocol Summarizer: Sendable {
    func summarize(_ transcript: String) async throws -> String
}

enum Summary {
    /// The summary markdown, or a one-line note explaining why there isn't one, so a
    /// user who turned summaries on never finds them silently missing.
    @MainActor
    static func of(segments: [TranscriptSegment], settings: Settings) async -> String? {
        guard settings.summaryEnabled, !segments.isEmpty else { return nil }
        guard let summarizer = makeSummarizer(settings: settings) else {
            return unavailable("add an Anthropic API key in Settings")
        }
        do {
            return try await summarizer.summarize(transcriptText(segments))
        } catch {
            if Task.isCancelled { return nil }
            NSLog("Summary failed: \(error)")
            return unavailable(error.localizedDescription)
        }
    }

    static func unavailable(_ reason: String) -> String {
        "_Summary unavailable: \(reason)._"
    }

    static func transcriptText(_ segments: [TranscriptSegment]) -> String {
        segments
            .map { "[\($0.timestamp)] \($0.speaker.label): \($0.text)" }
            .joined(separator: "\n")
    }

    @MainActor
    private static func makeSummarizer(settings: Settings) -> Summarizer? {
        switch settings.summaryBackend {
        case .local:
            return OllamaSummarizer(model: settings.localSummaryModel)
        case .cloud:
            let key = settings.anthropicAPIKey
            guard !key.isEmpty else { return nil }
            return ClaudeSummarizer(apiKey: key)
        }
    }

    static func prompt(for transcript: String) -> String {
        """
        You are summarizing the transcript of a meeting or call. Write a short \
        summary as 2–4 markdown bullet points, then a section titled "## Action items" \
        listing concrete follow-ups as markdown checkboxes (`- [ ]`). If there are no \
        action items, write "_None._" under that heading. Output only the markdown, no preamble.

        Transcript:
        \(transcript)
        """
    }
}

struct OllamaSummarizer: Summarizer {
    let model: String
    private let endpoint = URL(string: "http://localhost:11434/api/generate")!

    func summarize(_ transcript: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        // Local models on a long call can take minutes; the 60s default gives up early.
        request.timeoutInterval = 600
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": Summary.prompt(for: transcript),
            "stream": false
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code != .cancelled {
            throw SummaryError.backendUnavailable("Ollama isn't reachable on localhost:11434")
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SummaryError.backendUnavailable(status == 404
                ? "Ollama has no model named \(model). Run `ollama pull \(model)`"
                : "Ollama returned \(status)")
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object?["response"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct ClaudeSummarizer: Summarizer {
    let apiKey: String
    let model = "claude-opus-5-5"

    func summarize(_ transcript: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.timeoutInterval = 300
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // On a safety decline, the API retries on a suitable model inside the same call.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            // Thinking is always on and counts toward this cap, so leave real headroom.
            "max_tokens": 16_000,
            "output_config": ["effort": "medium"],
            "fallbacks": "default",
            "messages": [["role": "user", "content": Summary.prompt(for: transcript)]]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SummaryError.backendUnavailable("No response from Anthropic API")
        }
        guard http.statusCode == 200 else {
            throw SummaryError.backendUnavailable("Anthropic API returned \(http.statusCode)")
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if object?["stop_reason"] as? String == "refusal" {
            throw SummaryError.backendUnavailable("Anthropic declined to summarize this transcript")
        }
        let blocks = object?["content"] as? [[String: Any]] ?? []
        let text = blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SummaryError: LocalizedError {
    case backendUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .backendUnavailable(let detail): return detail
        }
    }
}
