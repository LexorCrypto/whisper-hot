import Foundation

/// Single source of truth for HTTP endpoints across providers.
/// Both STT (audio transcription) and chat-completions URLs live here,
/// so adding a new provider or changing a base path is a one-line edit
/// instead of synchronized changes across multiple files.
enum Endpoints {
    enum OpenAI {
        static let stt = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        static let chat = URL(string: "https://api.openai.com/v1/chat/completions")!
    }

    enum OpenRouter {
        /// OpenRouter routes audio THROUGH /chat/completions with input_audio
        /// content parts, so STT and chat share the same URL.
        static let chat = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        static var stt: URL { chat }
    }

    enum Groq {
        static let stt = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        static let chat = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    }

    enum PolzaAI {
        static let stt = URL(string: "https://polza.ai/api/v1/audio/transcriptions")!
        static let chat = URL(string: "https://polza.ai/api/v1/chat/completions")!
    }
}
