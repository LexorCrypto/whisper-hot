import Foundation

/// Talks to `POST https://openrouter.ai/api/v1/chat/completions` using the
/// OpenAI-compatible audio-in-chat schema: the user message carries an
/// `input_audio` part with base64-encoded WAV, and the system prompt constrains
/// the model to emit only the verbatim transcript.
///
/// This is NOT a dedicated STT endpoint; it is a chat completion where we
/// prompt an audio-capable model (e.g. `openai/gpt-4o-audio-preview`) to
/// behave like a transcriber. Works because the updated plan confirms
/// OpenRouter supports audio input on compatible models.
final class OpenRouterAudioProvider: TranscriptionService {
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    /// OpenRouter does not publish an explicit chat-completions payload
    /// ceiling, but returns `413 Content Too Large` on oversized requests.
    /// Cap raw WAV bytes conservatively so we never ship anything the
    /// router is likely to reject. 8 MB raw ≈ 4 min at 16kHz mono 16-bit,
    /// which is more than enough for a dictation-style voice note; longer
    /// clips should go through the OpenAI dedicated STT endpoint (25 MB).
    private static let maxAudioBytes = 8 * 1024 * 1024
    private let defaultModel: String
    private let apiKeyProvider: @Sendable () throws -> String
    private let urlSession: URLSession

    init(
        model: String = "openai/gpt-4o-audio-preview",
        apiKeyProvider: @escaping @Sendable () throws -> String,
        urlSession: URLSession = .shared
    ) {
        self.defaultModel = model
        self.apiKeyProvider = apiKeyProvider
        self.urlSession = urlSession
    }

    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> TranscriptionResult {
        let apiKey: String
        do {
            apiKey = try apiKeyProvider()
        } catch {
            throw TranscriptionError.missingAPIKey
        }
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptionError.missingAPIKey
        }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL, options: .mappedIfSafe)
        } catch {
            throw TranscriptionError.audioFileUnreadable(underlying: error)
        }
        guard !audioData.isEmpty else {
            throw TranscriptionError.audioFileEmpty
        }
        guard audioData.count <= Self.maxAudioBytes else {
            throw TranscriptionError.audioFileTooLarge(
                bytes: audioData.count,
                limitBytes: Self.maxAudioBytes
            )
        }

        let base64 = audioData.base64EncodedString()
        let effectiveModel = options.model ?? defaultModel

        let systemPrompt = """
        You are a speech-to-text transcriber. Return ONLY the verbatim transcript of the audio \
        with correct punctuation and capitalization. No commentary, no prefixes, no explanations, \
        no quotation marks around the result.
        """

        var userText = "Transcribe this audio."
        if options.language != .auto {
            userText += " The spoken language is \(options.language.rawValue)."
        }
        if let prompt = options.prompt, !prompt.isEmpty {
            userText += " Context hints: \(prompt)"
        }

        let body: [String: Any] = [
            "model": effectiveModel,
            "modalities": ["text"],
            "temperature": 0.0,
            "messages": [
                ["role": "system", "content": systemPrompt],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": userText],
                        [
                            "type": "input_audio",
                            "input_audio": [
                                "data": base64,
                                "format": "wav"
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            throw TranscriptionError.invalidResponse
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Attribution headers — optional per OpenRouter docs, helps analytics
        // attribution and future rate-limit carve-outs.
        request.setValue("https://github.com/aleksejsupilin/whisper-local", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("WhisperHot", forHTTPHeaderField: "X-Title")
        // Audio-in-chat models can be slower than dedicated STT endpoints.
        request.timeoutInterval = 120
        request.httpBody = jsonData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw TranscriptionError.networkFailure(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw TranscriptionError.httpError(status: http.statusCode, body: bodyText)
        }

        struct ChatResponse: Decodable {
            let choices: [Choice]
            struct Choice: Decodable {
                let message: Message
                struct Message: Decodable {
                    // OpenRouter's schema allows a null content in edge cases;
                    // keep it optional so we can distinguish decode failure
                    // (invalidResponse) from a real empty response.
                    let content: String?
                }
            }
        }

        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw TranscriptionError.invalidResponse
        }

        guard let content = decoded.choices.first?.message.content else {
            throw TranscriptionError.emptyTranscript
        }

        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TranscriptionError.emptyTranscript
        }

        return TranscriptionResult(text: text, providerModel: effectiveModel)
    }
}
