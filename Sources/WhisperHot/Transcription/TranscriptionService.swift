import Foundation

/// Language hint sent to the STT provider. `.auto` means "do not send a language parameter —
/// let the provider detect".
enum TranscriptionLanguage: String, Codable, Equatable {
    case auto
    case en
    case ru
    case lv
    case de
    case fr
    case es
    case it
    case pt
    case pl
    case tr
    case uk
    case ja
    case ko
    case zh
}

struct TranscriptionOptions: Equatable {
    var language: TranscriptionLanguage = .auto
    /// Optional prompt to bias the transcription (names, domain terms, etc.).
    var prompt: String? = nil
    /// Optional model override. If nil, the provider uses its init-time default.
    var model: String? = nil
}

struct TranscriptionResult: Equatable, Sendable {
    let text: String
    let providerModel: String
    /// Optional provenance for post-processing that ran AFTER the provider's
    /// transcribe() returned. Providers themselves never set this — it is
    /// populated by MenuBarController when LLMPostProcessor is enabled, so
    /// downstream code (and Block 13 history) can distinguish three states
    /// cleanly instead of string-concatenating everything into providerModel.
    var postProcessing: PostProcessingOutcome?

    init(text: String, providerModel: String, postProcessing: PostProcessingOutcome? = nil) {
        self.text = text
        self.providerModel = providerModel
        self.postProcessing = postProcessing
    }
}

/// What happened to a transcript after the raw STT result was handed off to
/// optional LLM cleanup.
/// - `nil` on `TranscriptionResult.postProcessing` means "feature disabled /
///   not applicable".
enum PostProcessingOutcome: Equatable, Sendable {
    case succeeded(model: String, preset: String)
    case failed(reason: String)
}

/// A single-call speech-to-text provider. Implementations must be thread-safe
/// because they will be invoked from async code on arbitrary executors.
protocol TranscriptionService: Sendable {
    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> TranscriptionResult
}
