import Foundation

enum AudioError: LocalizedError {
    case alreadyRecording
    case notRecording
    case microphoneAccessDenied
    case invalidInputFormat
    case converterUnavailable
    case engineStartFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Recording is already in progress."
        case .notRecording:
            return "No active recording."
        case .microphoneAccessDenied:
            return "Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone."
        case .invalidInputFormat:
            return "Invalid audio input format."
        case .converterUnavailable:
            return "Could not create audio converter for the current input format."
        case .engineStartFailed(let err):
            return "Audio engine failed to start: \(err.localizedDescription)"
        }
    }
}
