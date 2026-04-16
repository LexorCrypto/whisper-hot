import Foundation

/// Wraps a primary (cloud) transcription service with an offline fallback
/// (local whisper.cpp). If the primary fails with a network error and the
/// fallback is available, retries locally.
///
///   Cloud provider ──[network error]──► Local whisper.cpp
///
/// Only triggers on definitive offline errors (notConnectedToInternet,
/// networkConnectionLost). Does NOT trigger on timeouts (slow provider ≠ offline).
final class FallbackTranscriptionService: TranscriptionService {
    private let primary: TranscriptionService
    private let fallback: TranscriptionService?

    init(primary: TranscriptionService, fallback: TranscriptionService?) {
        self.primary = primary
        self.fallback = fallback
    }

    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> TranscriptionResult {
        do {
            let result = try await primary.transcribe(audioURL: audioURL, options: options)
            return result
        } catch {
            guard let fallback, isOfflineError(error) else {
                throw error
            }

            NSLog("WhisperHot: primary provider offline, falling back to local whisper")

            let localResult = try await fallback.transcribe(audioURL: audioURL, options: options)

            // Mark the result as coming from offline fallback so the caller
            // can skip post-processing and show an appropriate banner.
            return TranscriptionResult(
                text: localResult.text,
                providerModel: localResult.providerModel,
                postProcessing: localResult.postProcessing,
                usedOfflineFallback: true
            )
        }
    }

    private func isOfflineError(_ error: Error) -> Bool {
        // Check TranscriptionError.networkFailure wrapping a URLError
        if case TranscriptionError.networkFailure(let underlying) = error {
            return isOfflineURLError(underlying)
        }
        // Direct URLError
        return isOfflineURLError(error)
    }

    private func isOfflineURLError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return true
        default:
            return false
        }
    }
}
