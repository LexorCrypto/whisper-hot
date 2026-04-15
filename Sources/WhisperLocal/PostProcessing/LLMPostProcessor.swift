import Foundation

/// Text-in / text-out LLM call that applies a `PostProcessingPreset`
/// transformation to a raw transcript. Uses OpenRouter's /chat/completions
/// endpoint with a plain text user turn (no audio). The caller owns the
/// OpenRouter API key via Keychain.
final class LLMPostProcessor: @unchecked Sendable {
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let apiKeyProvider: @Sendable () throws -> String
    private let urlSession: URLSession

    init(
        apiKeyProvider: @escaping @Sendable () throws -> String,
        urlSession: URLSession = .shared
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.urlSession = urlSession
    }

    func process(text: String, options: PostProcessingOptions) async throws -> String {
        let apiKey: String
        do {
            apiKey = try apiKeyProvider()
        } catch {
            throw PostProcessingError.missingAPIKey
        }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw PostProcessingError.missingAPIKey
        }

        let systemPrompt = options.preset.systemPrompt(custom: options.customPrompt)

        let body: [String: Any] = [
            "model": options.model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ]
        ]

        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            throw PostProcessingError.invalidResponse
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://github.com/aleksejsupilin/whisper-local", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("WhisperLocal", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 60
        request.httpBody = jsonData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw PostProcessingError.networkFailure(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw PostProcessingError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw PostProcessingError.httpError(status: http.statusCode, body: bodyText)
        }

        struct ChatResponse: Decodable {
            let choices: [Choice]
            struct Choice: Decodable {
                let message: Message
                struct Message: Decodable {
                    let content: String?
                }
            }
        }

        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw PostProcessingError.invalidResponse
        }

        guard let content = decoded.choices.first?.message.content else {
            throw PostProcessingError.emptyResponse
        }

        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else {
            throw PostProcessingError.emptyResponse
        }
        return result
    }
}
