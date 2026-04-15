import Foundation

/// Talks to any `/v1/audio/transcriptions`-compatible endpoint.
/// - OpenAI proper: `https://api.openai.com/v1/audio/transcriptions`
/// - Groq mirror:   `https://api.groq.com/openai/v1/audio/transcriptions`
///
/// Groq exposes an OpenAI-compatible wire format, so we use the same class
/// for both — only the endpoint URL, default model, and per-provider size
/// cap differ.
///
/// Published upload limits (as of April 2026):
/// - OpenAI: hard 25 MB
/// - Groq free tier: 25 MB
/// - Groq dev tier: 100 MB (plus URL-based upload for larger files)
///
/// The `maxAudioBytes` cap below is app-imposed. We default to 25 MB as a
/// safe floor and let the caller raise it for tiers that support more.
final class OpenAICompatibleSTTProvider: TranscriptionService {
    private let endpoint: URL
    private let model: String
    private let maxAudioBytes: Int
    private let apiKeyProvider: @Sendable () throws -> String
    private let urlSession: URLSession

    init(
        endpoint: URL,
        model: String,
        maxAudioBytes: Int = 25 * 1024 * 1024,
        apiKeyProvider: @escaping @Sendable () throws -> String,
        urlSession: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.model = model
        self.maxAudioBytes = maxAudioBytes
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

        // Voice recordings are a few hundred KB to a few MB; mappedIfSafe is
        // the right hint. Streaming multipart upload is a future optimization.
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL, options: .mappedIfSafe)
        } catch {
            throw TranscriptionError.audioFileUnreadable(underlying: error)
        }
        guard !audioData.isEmpty else {
            throw TranscriptionError.audioFileEmpty
        }
        guard audioData.count <= maxAudioBytes else {
            throw TranscriptionError.audioFileTooLarge(
                bytes: audioData.count,
                limitBytes: maxAudioBytes
            )
        }

        let effectiveModel = options.model ?? model

        let boundary = "WhisperHotBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        var body = Data()
        appendPart(&body, boundary: boundary, name: "file",
                   filename: audioURL.lastPathComponent,
                   contentType: "audio/wav", data: audioData)
        appendPart(&body, boundary: boundary, name: "model", value: effectiveModel)
        if options.language != .auto {
            appendPart(&body, boundary: boundary, name: "language", value: options.language.rawValue)
        }
        if let prompt = options.prompt, !prompt.isEmpty {
            appendPart(&body, boundary: boundary, name: "prompt", value: prompt)
        }
        appendPart(&body, boundary: boundary, name: "response_format", value: "json")
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

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

        struct STTResponse: Decodable { let text: String }
        let decoded: STTResponse
        do {
            decoded = try JSONDecoder().decode(STTResponse.self, from: data)
        } catch {
            throw TranscriptionError.invalidResponse
        }
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TranscriptionError.emptyTranscript
        }
        return TranscriptionResult(text: text, providerModel: effectiveModel)
    }

    // MARK: - Multipart helpers

    private func appendPart(
        _ body: inout Data,
        boundary: String,
        name: String,
        value: String
    ) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append(value.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
    }

    private func appendPart(
        _ body: inout Data,
        boundary: String,
        name: String,
        filename: String,
        contentType: String,
        data: Data
    ) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }
}
