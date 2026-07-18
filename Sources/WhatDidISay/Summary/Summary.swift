import Foundation

protocol Summarizer: Sendable {
    func summarize(_ transcript: String) async throws -> String
}

enum Summary {
    @MainActor
    static func of(segments: [TranscriptSegment], settings: Settings) async -> String? {
        guard let summarizer = makeSummarizer(settings: settings), !segments.isEmpty else {
            return nil
        }
        return try? await summarizer.summarize(transcriptText(segments))
    }

    static func transcriptText(_ segments: [TranscriptSegment]) -> String {
        segments
            .map { "[\($0.timestamp)] \($0.speaker.label): \($0.text)" }
            .joined(separator: "\n")
    }

    @MainActor
    private static func makeSummarizer(settings: Settings) -> Summarizer? {
        guard settings.summaryEnabled else { return nil }
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
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": Summary.prompt(for: transcript),
            "stream": false
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SummaryError.backendUnavailable("Ollama not reachable on localhost:11434")
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object?["response"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct ClaudeSummarizer: Summarizer {
    let apiKey: String
    let model = "claude-opus-4-8"

    func summarize(_ transcript: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": 1024,
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
