import XCTest
@testable import WhisperHotLib

final class FallbackTranscriptionServiceTests: XCTestCase {
    func testAutoOfflineTimeoutReturnsFallbackResult() async throws {
        let primary = DelayedMockTranscriptionService(
            delayNanoseconds: 10_000_000_000,
            result: TranscriptionResult(text: "cloud", providerModel: "cloud-model")
        )
        let fallback = DelayedMockTranscriptionService(
            delayNanoseconds: 10_000_000,
            result: TranscriptionResult(text: "local", providerModel: "local-model")
        )
        let service = FallbackTranscriptionService(
            primary: primary,
            fallback: fallback,
            autoOfflineOnTimeout: true,
            autoOfflineTimeoutSeconds: 1
        )

        let result = try await service.transcribe(
            audioURL: URL(fileURLWithPath: "/tmp/mock.wav"),
            options: TranscriptionOptions()
        )

        XCTAssertEqual(result.text, "local")
        XCTAssertEqual(result.providerModel, "local-model")
        XCTAssertTrue(result.usedOfflineFallback)
    }

    func testPrimaryWinsWhenFasterThanTimeout() async throws {
        let primary = DelayedMockTranscriptionService(
            delayNanoseconds: 50_000_000,
            result: TranscriptionResult(text: "cloud", providerModel: "cloud-model")
        )
        let fallback = DelayedMockTranscriptionService(
            delayNanoseconds: 10_000_000_000,
            result: TranscriptionResult(text: "local", providerModel: "local-model")
        )
        let service = FallbackTranscriptionService(
            primary: primary,
            fallback: fallback,
            autoOfflineOnTimeout: true,
            autoOfflineTimeoutSeconds: 5
        )

        let result = try await service.transcribe(
            audioURL: URL(fileURLWithPath: "/tmp/mock.wav"),
            options: TranscriptionOptions()
        )

        XCTAssertEqual(result.text, "cloud")
        XCTAssertEqual(result.providerModel, "cloud-model")
        XCTAssertFalse(result.usedOfflineFallback)
    }

    func testNonOfflinePrimaryFailureBeforeTimeoutPreservesError() async throws {
        // 401/403/5xx-style failure that arrives before the timer fires
        // must propagate, not silently fall back. Preserves ADR-013.
        let primary = FailingMockTranscriptionService(
            delayNanoseconds: 50_000_000,
            error: TranscriptionError.invalidResponse
        )
        let fallback = DelayedMockTranscriptionService(
            delayNanoseconds: 10_000_000,
            result: TranscriptionResult(text: "local", providerModel: "local-model")
        )
        let service = FallbackTranscriptionService(
            primary: primary,
            fallback: fallback,
            autoOfflineOnTimeout: true,
            autoOfflineTimeoutSeconds: 5
        )

        do {
            _ = try await service.transcribe(
                audioURL: URL(fileURLWithPath: "/tmp/mock.wav"),
                options: TranscriptionOptions()
            )
            XCTFail("expected non-offline error to propagate")
        } catch TranscriptionError.invalidResponse {
            // expected
        }
    }

    func testToggleOffPreservesLegacyBehavior() async throws {
        let primary = DelayedMockTranscriptionService(
            delayNanoseconds: 50_000_000,
            result: TranscriptionResult(text: "cloud", providerModel: "cloud-model")
        )
        let fallback = DelayedMockTranscriptionService(
            delayNanoseconds: 10_000_000,
            result: TranscriptionResult(text: "local", providerModel: "local-model")
        )
        let service = FallbackTranscriptionService(
            primary: primary,
            fallback: fallback,
            autoOfflineOnTimeout: false,
            autoOfflineTimeoutSeconds: 1
        )

        let result = try await service.transcribe(
            audioURL: URL(fileURLWithPath: "/tmp/mock.wav"),
            options: TranscriptionOptions()
        )

        XCTAssertEqual(result.text, "cloud")
        XCTAssertFalse(result.usedOfflineFallback)
    }
}

private final class DelayedMockTranscriptionService: TranscriptionService {
    private let delayNanoseconds: UInt64
    private let result: TranscriptionResult

    init(delayNanoseconds: UInt64, result: TranscriptionResult) {
        self.delayNanoseconds = delayNanoseconds
        self.result = result
    }

    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> TranscriptionResult {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return result
    }
}

private final class FailingMockTranscriptionService: TranscriptionService {
    private let delayNanoseconds: UInt64
    private let error: Error

    init(delayNanoseconds: UInt64, error: Error) {
        self.delayNanoseconds = delayNanoseconds
        self.error = error
    }

    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> TranscriptionResult {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        throw error
    }
}
