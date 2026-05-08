import AppKit
import Foundation

/// Encapsulates the full transcription pipeline: provider selection,
/// fallback, context routing, word replacements, and post-processing.
/// Extracted from MenuBarController to reduce god-object complexity.
///
///   AudioURL → TranscriptionCoordinator → TranscriptionResult
///
/// All methods are Sendable-safe for use in Task.detached.
struct TranscriptionCoordinator: Sendable {
    let service: TranscriptionService
    let postProcessor: LLMPostProcessor?
    let localLLMProcessor: LocalLLMProcessor?
    let postProcessingOptions: PostProcessingOptions?
    let wordReplacements: [WordReplacement]

    /// Run the full pipeline: transcribe → word replace → post-process.
    enum Outcome: Sendable {
        case success(TranscriptionResult)
        case failure(String)
    }

    func run(audioURL: URL, options: TranscriptionOptions) async -> Outcome {
        do {
            let raw = try await service.transcribe(audioURL: audioURL, options: options)

            // Apply word replacements before post-processing
            let fixedText = wordReplacements.isEmpty
                ? raw.text
                : WordReplacement.applyAll(wordReplacements, to: raw.text)
            var finalResult = TranscriptionResult(
                text: fixedText,
                providerModel: raw.providerModel,
                postProcessing: raw.postProcessing,
                usedOfflineFallback: raw.usedOfflineFallback
            )

            // Skip post-processing if offline fallback was used
            if raw.usedOfflineFallback {
                NSLog("WhisperHot: offline fallback used, skipping post-processing")
            } else if let localLLM = localLLMProcessor, let ppOptions = postProcessingOptions {
                do {
                    let processed = try await localLLM.process(text: fixedText, options: ppOptions)
                    finalResult = TranscriptionResult(
                        text: processed,
                        providerModel: raw.providerModel,
                        postProcessing: .succeeded(model: "local-llm", preset: ppOptions.preset.rawValue)
                    )
                } catch {
                    NSLog("WhisperHot: local LLM failed")
                    finalResult = TranscriptionResult(
                        text: fixedText,
                        providerModel: raw.providerModel,
                        postProcessing: .failed(reason: error.localizedDescription)
                    )
                }
            } else if let postProcessor, let ppOptions = postProcessingOptions {
                do {
                    let processed = try await postProcessor.process(
                        text: fixedText,
                        options: ppOptions
                    )
                    finalResult = TranscriptionResult(
                        text: processed,
                        providerModel: raw.providerModel,
                        postProcessing: .succeeded(
                            model: ppOptions.model,
                            preset: ppOptions.preset.rawValue
                        )
                    )
                } catch {
                    NSLog("WhisperHot: post-processing failed")
                    finalResult = TranscriptionResult(
                        text: fixedText,
                        providerModel: raw.providerModel,
                        postProcessing: .failed(reason: error.localizedDescription)
                    )
                }
            }

            return .success(finalResult)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Factory

    /// Build a coordinator from current Preferences snapshot.
    /// Must be called on the main actor (reads Preferences + Keychain).
    @MainActor
    static func fromPreferences(
        provider: TranscriptionProvider,
        recordingTarget: NSRunningApplication?,
        wantsRawOutput: Bool
    ) -> TranscriptionCoordinator {
        let primaryService = makeTranscriptionService(for: provider)
        let localFallback = makeLocalFallbackIfReady()
        // Timeout race only makes sense when primary is a cloud provider.
        // If the user explicitly selected local whisper as primary, the
        // timer would just fire on slow local transcriptions and start a
        // duplicate local subprocess on the same audio. ADR-014 §Последствия.
        let timeoutRaceEligible = provider != .localWhisper && Preferences.autoOfflineOnTimeout
        let service: TranscriptionService = FallbackTranscriptionService(
            primary: primaryService,
            fallback: localFallback,
            autoOfflineOnTimeout: timeoutRaceEligible,
            autoOfflineTimeoutSeconds: Preferences.autoOfflineTimeoutSeconds
        )

        let skipPostProcessing = wantsRawOutput || !Preferences.postProcessingEnabled
        let ppProvider = Preferences.ppProvider

        let postProcessor: LLMPostProcessor?
        let localLLMProcessor: LocalLLMProcessor?

        if skipPostProcessing {
            postProcessor = nil
            localLLMProcessor = nil
        } else if ppProvider == .localLLM {
            // Always construct the processor; let process() surface the
            // missingLocalBinary / missingLocalModel errors at run time so
            // the user sees a meaningful banner instead of silent skipping
            // when paths are empty.
            postProcessor = nil
            localLLMProcessor = LocalLLMProcessor(
                binaryPath: Preferences.localLLMBinaryPath,
                modelPath: Preferences.localLLMModelPath
            )
        } else if let endpoint = ppProvider.endpoint, let account = ppProvider.keychainAccount {
            postProcessor = LLMPostProcessor(
                endpoint: endpoint,
                apiKeyProvider: { try Keychain.readAPIKey(account: account) },
                extraHeaders: ppProvider.extraHeaders
            )
            localLLMProcessor = nil
        } else {
            postProcessor = nil
            localLLMProcessor = nil
        }

        var ppOptions = Preferences.currentPostProcessingOptions
        if !skipPostProcessing && Preferences.contextRoutingEnabled {
            let resolved = ContextRouter.resolve(
                target: recordingTarget,
                rules: Preferences.contextRules
            )
            ppOptions.preset = resolved
            NSLog("WhisperHot: context route → \(recordingTarget?.bundleIdentifier ?? "nil") → \(resolved.rawValue)")
        }
        let postProcessingOptions: PostProcessingOptions? = skipPostProcessing ? nil : ppOptions

        // vocabularyHints are read in MenuBarController and passed via TranscriptionOptions.prompt.
        let wordReplacements = Preferences.wordReplacements

        return TranscriptionCoordinator(
            service: service,
            postProcessor: postProcessor,
            localLLMProcessor: localLLMProcessor,
            postProcessingOptions: postProcessingOptions,
            wordReplacements: wordReplacements
        )
    }

    // MARK: - Provider factories

    private static func makeTranscriptionService(for provider: TranscriptionProvider) -> TranscriptionService {
        switch provider {
        case .openai:
            return OpenAICompatibleSTTProvider(
                endpoint: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
                model: Preferences.modelOpenAI,
                apiKeyProvider: { try Keychain.readAPIKey(account: .openAI) }
            )
        case .openRouter:
            return OpenRouterAudioProvider(
                model: Preferences.modelOpenRouter,
                apiKeyProvider: { try Keychain.readAPIKey(account: .openRouter) }
            )
        case .groq:
            return OpenAICompatibleSTTProvider(
                endpoint: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!,
                model: Preferences.modelGroq,
                apiKeyProvider: { try Keychain.readAPIKey(account: .groq) }
            )
        case .polzaAI:
            return OpenAICompatibleSTTProvider(
                endpoint: URL(string: "https://polza.ai/api/v1/audio/transcriptions")!,
                model: Preferences.modelOpenAI,
                apiKeyProvider: { try Keychain.readAPIKey(account: .polzaAI) }
            )
        case .localWhisper:
            return LocalWhisperProvider(
                binaryPath: Preferences.localWhisperBinaryPath,
                modelPath: Preferences.localWhisperModelPath
            )
        }
    }

    private static func makeLocalFallbackIfReady() -> TranscriptionService? {
        guard Preferences.isLocalWhisperReady else { return nil }
        return LocalWhisperProvider(
            binaryPath: Preferences.localWhisperBinaryPath,
            modelPath: Preferences.localWhisperModelPath
        )
    }
}
