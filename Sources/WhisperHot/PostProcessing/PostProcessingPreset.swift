import Foundation

/// Preset cleanup / rewrite instructions applied to a raw transcript before
/// it reaches the pasteboard. All presets emit a single system prompt; the
/// user's transcript is sent as the user turn.
enum PostProcessingPreset: String, CaseIterable, Identifiable, Sendable {
    case cleanup
    case emailStyle = "email"
    case slackCasual = "slack"
    case technical
    case translateEnglish = "translate_en"
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cleanup: return "Cleanup (remove fillers, fix punctuation)"
        case .emailStyle: return "Email style (polite, formal)"
        case .slackCasual: return "Slack casual"
        case .technical: return "Technical documentation"
        case .translateEnglish: return "Translate to English"
        case .custom: return "Custom prompt"
        }
    }

    /// The system-level transformation instruction sent to the LLM.
    /// `custom` falls back to a minimal cleanup instruction if the user
    /// hasn't written their own prompt yet.
    func systemPrompt(custom: String?) -> String {
        let guard_ = "You are a text editor that transforms raw voice-to-text transcripts. Return ONLY the transformed text with no commentary, prefixes, explanations, apologies, or surrounding quotation marks."
        let instructions: String
        switch self {
        case .cleanup:
            instructions = "Remove filler words (um, uh, like, you know, so, basically). Fix punctuation and capitalization. Preserve every fact and the speaker's intent. Do not paraphrase, do not summarize."
        case .emailStyle:
            instructions = "Rewrite as a polite, well-structured professional email body. Preserve meaning. Use full sentences and paragraph breaks. Do not add a subject or greeting unless the original already contained one."
        case .slackCasual:
            instructions = "Rewrite as a casual Slack message. Short friendly sentences. No greetings, no sign-offs. Preserve meaning."
        case .technical:
            instructions = "Reformat as clear technical documentation. Use bullet points where the speaker listed items, use fenced code blocks for anything that is clearly code or a command. Preserve accuracy above all else."
        case .translateEnglish:
            instructions = "Translate the text to natural English. Preserve meaning, tone, and technical terms. If the text is already in English, return it unchanged apart from light punctuation cleanup."
        case .custom:
            let trimmed = (custom ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            instructions = trimmed.isEmpty
                ? "Clean up this transcript: remove fillers, fix punctuation, preserve meaning."
                : trimmed
        }
        return guard_ + "\n\n" + instructions
    }
}

/// Fully resolved post-processing configuration — captured into the
/// background task so we don't read Preferences off the main actor later.
struct PostProcessingOptions: Sendable, Equatable {
    var preset: PostProcessingPreset
    var customPrompt: String
    var model: String
}

enum PostProcessingError: LocalizedError {
    case missingAPIKey
    case networkFailure(underlying: Error)
    case httpError(status: Int, body: String)
    case invalidResponse
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenRouter API key is not set for post-processing. Open Settings and save a key."
        case .networkFailure(let err):
            return "Post-processing network error: \(err.localizedDescription)"
        case .httpError(let status, let body):
            let truncated = body.count > 300 ? String(body.prefix(300)) + "…" : body
            return "Post-processing HTTP \(status): \(truncated)"
        case .invalidResponse:
            return "Unexpected response shape from post-processing API."
        case .emptyResponse:
            return "Post-processing returned an empty response."
        }
    }
}
