import Foundation

enum TranscriptionError: LocalizedError {
    case missingAPIKey
    case audioFileUnreadable(underlying: Error)
    case audioFileEmpty
    case audioFileTooLarge(bytes: Int, limitBytes: Int)
    case networkFailure(underlying: Error)
    case httpError(status: Int, body: String)
    case invalidResponse
    case emptyTranscript
    case localBinaryNotFound(path: String)
    case localModelNotFound(path: String)
    case localProcessFailed(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key is not set. Open Settings and paste your key."
        case .audioFileUnreadable(let err):
            return "Could not read the recorded audio file: \(err.localizedDescription)"
        case .audioFileEmpty:
            return "Audio file is empty — nothing to transcribe."
        case .audioFileTooLarge(let bytes, let limit):
            let fmt = ByteCountFormatter()
            fmt.countStyle = .binary
            return "Audio file is \(fmt.string(fromByteCount: Int64(bytes))). The selected provider rejects anything over \(fmt.string(fromByteCount: Int64(limit))). Record a shorter clip."
        case .networkFailure(let err):
            return "Network error: \(err.localizedDescription)"
        case .httpError(let status, let body):
            let truncated = body.count > 300 ? String(body.prefix(300)) + "…" : body
            return "HTTP \(status): \(truncated)"
        case .invalidResponse:
            return "Unexpected response shape from transcription API."
        case .emptyTranscript:
            return "Transcription returned an empty text."
        case .localBinaryNotFound(let path):
            return path.isEmpty
                ? "Local Whisper binary path is not set. Open Settings and point it at your whisper.cpp executable."
                : "Local Whisper binary not found or not executable at \(path)."
        case .localModelNotFound(let path):
            return path.isEmpty
                ? "Local Whisper model path is not set. Open Settings and point it at a GGML model file."
                : "Local Whisper model not found at \(path)."
        case .localProcessFailed(let exitCode, let stderr):
            let truncated = stderr.count > 300 ? String(stderr.prefix(300)) + "…" : stderr
            return "Local Whisper exited with code \(exitCode): \(truncated)"
        }
    }
}
