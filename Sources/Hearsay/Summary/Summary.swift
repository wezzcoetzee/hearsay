import Foundation

protocol Summarizer: Sendable {
    func summarize(_ transcript: String) async throws -> String
}

/// What the summarizer gave back: the summary markdown, plus a short topic for the
/// note's title and filename when the model offered one.
struct NoteSummary: Equatable, Sendable {
    var topic: String?
    var markdown: String
    /// Why there's no real summary, in plain words, when the summarizer couldn't make
    /// one. The menu shows it on the saved note, so the user hears before opening it.
    var failure: String?

    private static let topicPrefix = "topic:"

    /// Splits the model's `Topic: …` opening line from the summary below it. Models
    /// sometimes bold the line or skip it, so both are tolerated.
    init(parsing raw: String) {
        var lines = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        let first = lines.first?.trimmingCharacters(in: CharacterSet(charactersIn: "*_# ")) ?? ""
        guard first.lowercased().hasPrefix(Self.topicPrefix) else {
            self.init(topic: nil, markdown: raw.trimmingCharacters(in: .whitespacesAndNewlines))
            return
        }
        lines.removeFirst()
        let topic = first.dropFirst(Self.topicPrefix.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "*_\"'. ").union(.whitespaces))
        self.init(
            topic: topic.isEmpty ? nil : topic,
            markdown: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    init(topic: String?, markdown: String, failure: String? = nil) {
        self.topic = topic
        self.markdown = markdown
        self.failure = failure
    }
}

enum Summary {
    /// The summary, or a one-line note explaining why there isn't one, so a user who
    /// turned summaries on never finds them silently missing.
    @MainActor
    static func of(segments: [TranscriptSegment], settings: Settings) async -> NoteSummary? {
        guard settings.summaryEnabled, !segments.isEmpty else { return nil }
        guard let summarizer = makeSummarizer(settings: settings) else {
            return unavailable("add an Anthropic API key in Settings")
        }
        do {
            return NoteSummary(parsing: try await summarizer.summarize(transcriptText(segments)))
        } catch {
            if Task.isCancelled { return nil }
            NSLog("Summary failed: \(error)")
            return unavailable(plainReason(for: error, backend: settings.summaryBackend))
        }
    }

    static func unavailable(_ reason: String) -> NoteSummary {
        NoteSummary(topic: nil, markdown: "_Summary unavailable: \(reason)._", failure: reason)
    }

    /// The common failures in words a user can act on; anything else as the system
    /// describes it.
    static func plainReason(for error: Error, backend: SummaryBackend) -> String {
        let unreachable: Set<URLError.Code> = [
            .cannotConnectToHost, .cannotFindHost, .networkConnectionLost,
            .notConnectedToInternet, .timedOut,
        ]
        if let urlError = error as? URLError, unreachable.contains(urlError.code) {
            return backend == .local ? "Ollama isn't running" : "Anthropic couldn't be reached"
        }
        return error.localizedDescription
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
            // A pasted key often carries a trailing newline, which breaks the header.
            let key = settings.anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return ClaudeSummarizer(apiKey: key)
        }
    }

    static func prompt(for transcript: String) -> String {
        """
        You are summarizing the transcript of a meeting or call. Start with one line \
        `Topic: <what the call was about in 2 to 6 words>`. Then write a short \
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

    private static let charactersPerToken = 3.5
    private static let answerTokens = 2_048
    private static let contextRange = 4_096...32_768

    /// Ollama silently cuts a prompt that overflows its context window (a few thousand
    /// tokens by default), so the window is sized to the prompt plus room for the answer.
    static func contextLength(forPrompt prompt: String) -> Int {
        let promptTokens = Int((Double(prompt.count) / charactersPerToken).rounded(.up))
        return min(max(promptTokens + answerTokens, contextRange.lowerBound), contextRange.upperBound)
    }

    func summarize(_ transcript: String) async throws -> String {
        let prompt = Summary.prompt(for: transcript)
        var request = URLRequest(url: endpoint)
        // Local models on a long call can take minutes; the 60s default gives up early.
        request.timeoutInterval = 600
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": ["num_ctx": Self.contextLength(forPrompt: prompt)],
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code != .cancelled {
            throw SummaryError.backendUnavailable(
                error.code == .timedOut
                    ? "Ollama timed out before finishing the summary"
                    : "Ollama isn't reachable on localhost:11434")
        }
        return try Self.parse(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0, model: model)
    }

    static func parse(_ data: Data, status: Int, model: String) throws -> String {
        guard status == 200 else {
            throw SummaryError.backendUnavailable(
                status == 404
                    ? "Ollama has no model named \(model). Run `ollama pull \(model)`"
                    : "Ollama returned \(status)")
        }
        struct Reply: Decodable { let response: String }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw SummaryError.backendUnavailable("Ollama sent a reply that couldn't be read")
        }
        let text = reply.response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw SummaryError.backendUnavailable("Ollama returned an empty response") }
        return text
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
            "messages": [["role": "user", "content": Summary.prompt(for: transcript)]],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SummaryError.backendUnavailable("No response from Anthropic API")
        }
        return try Self.parse(data, status: http.statusCode)
    }

    static func parse(_ data: Data, status: Int) throws -> String {
        struct ErrorReply: Decodable {
            struct Detail: Decodable { let message: String }
            let error: Detail
        }
        guard status == 200 else {
            let detail = (try? JSONDecoder().decode(ErrorReply.self, from: data))?.error.message
            throw SummaryError.backendUnavailable(
                ["Anthropic API returned \(status)", detail].compactMap { $0 }.joined(separator: ": "))
        }

        struct Reply: Decodable {
            struct Block: Decodable {
                let type: String
                let text: String?
            }
            let stopReason: String?
            let content: [Block]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let reply = try? decoder.decode(Reply.self, from: data) else {
            throw SummaryError.backendUnavailable("Anthropic sent a reply that couldn't be read")
        }
        switch reply.stopReason {
        case "refusal":
            throw SummaryError.backendUnavailable("Anthropic declined to summarize this transcript")
        case "max_tokens":
            throw SummaryError.backendUnavailable("Claude ran out of output tokens before finishing the summary")
        default:
            break
        }
        let text = reply.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw SummaryError.backendUnavailable("Claude replied without any text") }
        return text
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
