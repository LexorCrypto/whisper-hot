import Foundation

/// Wraps a primary (cloud) transcription service with an offline fallback
/// (local whisper.cpp). If the primary fails with a network error and the
/// fallback is available, retries locally.
///
///   Cloud provider ──[network error]──► Local whisper.cpp
///
/// By default, only triggers on definitive offline errors
/// (notConnectedToInternet, networkConnectionLost) — see ADR-013.
/// If `autoOfflineOnTimeout` is enabled in Preferences, also races primary
/// against a timer (NOT against a concurrent local subprocess) and switches
/// to local whisper.cpp after the configured timeout (ADR-014).
/// 401/403/5xx still do NOT trigger fallback regardless of the toggle.
final class FallbackTranscriptionService: TranscriptionService {
    private let primary: TranscriptionService
    private let fallback: TranscriptionService?
    private let autoOfflineOnTimeout: Bool
    private let autoOfflineTimeoutSeconds: Int

    init(
        primary: TranscriptionService,
        fallback: TranscriptionService?,
        autoOfflineOnTimeout: Bool = false,
        autoOfflineTimeoutSeconds: Int = 10
    ) {
        self.primary = primary
        self.fallback = fallback
        self.autoOfflineOnTimeout = autoOfflineOnTimeout
        self.autoOfflineTimeoutSeconds = max(1, autoOfflineTimeoutSeconds)
    }

    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> TranscriptionResult {
        if autoOfflineOnTimeout, let fallback {
            return try await transcribeWithTimeoutRace(
                audioURL: audioURL,
                options: options,
                fallback: fallback
            )
        }

        do {
            return try await primary.transcribe(audioURL: audioURL, options: options)
        } catch {
            guard let fallback, isOfflineError(error) else {
                throw error
            }

            NSLog("WhisperHot: primary provider offline, falling back to local whisper")

            let localResult = try await fallback.transcribe(audioURL: audioURL, options: options)
            return markedOfflineFallback(localResult)
        }
    }

    // MARK: - Race implementation
    //
    // Race primary against a timer ONLY. The local fallback is started
    // sequentially AFTER the race resolves with .timeout or .primaryFailure
    // (offline). This avoids waiting on `LocalWhisperProvider`'s subprocess
    // — which does not observe Task cancellation — when primary wins fast.

    private enum RaceEvent {
        case primarySuccess(TranscriptionResult)
        case primaryFailure(Error)
        case timeout
    }

    private func transcribeWithTimeoutRace(
        audioURL: URL,
        options: TranscriptionOptions,
        fallback: TranscriptionService
    ) async throws -> TranscriptionResult {
        // Clamp to a sane range so a corrupted UserDefaults value can't
        // overflow UInt64 or stall the app for years.
        let clampedSeconds = max(1, min(autoOfflineTimeoutSeconds, 3600))
        let timeoutNanoseconds = UInt64(clampedSeconds) * 1_000_000_000
        let primary = self.primary

        let raceResult: RaceEvent = try await withThrowingTaskGroup(of: RaceEvent.self) { group in
            group.addTask {
                do {
                    let result = try await primary.transcribe(audioURL: audioURL, options: options)
                    return .primarySuccess(result)
                } catch {
                    // Re-raise on cancellation (URLError.cancelled or CancellationError).
                    // Do NOT convert to .primaryFailure — that would start local fallback
                    // after the caller has already aborted.
                    if Task.isCancelled { throw CancellationError() }
                    return .primaryFailure(error)
                }
            }

            group.addTask {
                // Use plain `try` (not `try?`) so parent-task cancellation throws out
                // of the group instead of being silently converted into a .timeout
                // event that would kick off local transcription post-cancel.
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                return .timeout
            }

            guard let first = try await group.next() else {
                throw TranscriptionError.invalidResponse
            }
            group.cancelAll()
            return first
        }

        switch raceResult {
        case .primarySuccess(let result):
            return result

        case .primaryFailure(let error):
            if isOfflineError(error) {
                NSLog("WhisperHot: primary provider offline, falling back to local whisper")
                let localResult = try await fallback.transcribe(audioURL: audioURL, options: options)
                return markedOfflineFallback(localResult)
            }
            throw error

        case .timeout:
            NSLog("WhisperHot: primary provider timed out after \(autoOfflineTimeoutSeconds)s, switching to local whisper")
            let localResult = try await fallback.transcribe(audioURL: audioURL, options: options)
            return markedOfflineFallback(localResult)
        }
    }

    private func markedOfflineFallback(_ result: TranscriptionResult) -> TranscriptionResult {
        TranscriptionResult(
            text: result.text,
            providerModel: result.providerModel,
            postProcessing: result.postProcessing,
            usedOfflineFallback: true
        )
    }

    // MARK: - Offline error detection

    private func isOfflineError(_ error: Error) -> Bool {
        if case TranscriptionError.networkFailure(let underlying) = error {
            return isOfflineURLError(underlying)
        }
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
