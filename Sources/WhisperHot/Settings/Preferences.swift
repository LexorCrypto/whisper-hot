import Carbon.HIToolbox
import Foundation

/// Central namespace for every user-facing preference backed by UserDefaults.
/// SwiftUI code binds via `@AppStorage(Preferences.Key.X)`; non-SwiftUI code
/// reads via the typed accessors below.
enum Preferences {
    enum Key {
        static let provider = "WhisperHot.provider"
        static let modelOpenAI = "WhisperHot.modelOpenAI"
        static let modelOpenRouter = "WhisperHot.modelOpenRouter"
        static let modelGroq = "WhisperHot.modelGroq"
        static let localWhisperBinaryPath = "WhisperHot.localWhisperBinaryPath"
        static let localWhisperModelPath = "WhisperHot.localWhisperModelPath"
        static let language = "WhisperHot.language"
        static let autoPaste = "WhisperHot.autoPaste"
        static let sounds = "WhisperHot.sounds"
        static let indicatorStyle = "WhisperHot.indicatorStyle"
        static let postProcessingEnabled = "WhisperHot.postProcessingEnabled"
        static let postProcessingPreset = "WhisperHot.postProcessingPreset"
        static let postProcessingCustomPrompt = "WhisperHot.postProcessingCustomPrompt"
        static let postProcessingModel = "WhisperHot.postProcessingModel"
        static let historyEnabled = "WhisperHot.historyEnabled"
        static let historyRetentionDays = "WhisperHot.historyRetentionDays"
        static let historyMaxEntries = "WhisperHot.historyMaxEntries"
        static let audioRetention = "WhisperHot.audioRetention"
        static let fnKeyEnabled = "WhisperHot.fnKeyEnabled"
        static let hotkeyKeyCode = "WhisperHot.hotkeyKeyCode"
        static let hotkeyModifiers = "WhisperHot.hotkeyModifiers"
        static let contextRoutingEnabled = "WhisperHot.contextRoutingEnabled"
        static let contextRules = "WhisperHot.contextRules"
        static let postProcessingProvider = "WhisperHot.postProcessingProvider"
        static let postProcessingModelOpenAI = "WhisperHot.postProcessingModelOpenAI"
        static let postProcessingModelGroq = "WhisperHot.postProcessingModelGroq"
        static let customEndpointURL = "WhisperHot.customEndpointURL"
        static let customEndpointModel = "WhisperHot.customEndpointModel"
        static let appLanguage = "WhisperHot.appLanguage"
    }

    enum Defaults {
        static let provider = TranscriptionProvider.openai.rawValue
        static let modelOpenAI = "gpt-4o-mini-transcribe"
        static let modelOpenRouter = "openai/gpt-4o-audio-preview"
        static let modelGroq = "whisper-large-v3-turbo"
        static let localWhisperBinaryPath = ""
        static let localWhisperModelPath = ""
        static let language = TranscriptionLanguage.auto.rawValue
        static let autoPaste = true
        static let sounds = true
        static let indicatorStyle = IndicatorStyle.menubar.rawValue
        static let postProcessingEnabled = false
        static let postProcessingPreset = PostProcessingPreset.cleanup.rawValue
        static let postProcessingCustomPrompt = ""
        static let postProcessingModel = "openai/gpt-4o-mini"
        static let historyEnabled = false
        /// 0 = keep forever (subject to max-entries cap).
        static let historyRetentionDays = 0
        static let historyMaxEntries = 100
        static let audioRetention = AudioRetention.immediate.rawValue
        static let fnKeyEnabled = false
        static let hotkeyKeyCode = kVK_ANSI_5
        static let hotkeyModifiers = cmdKey | optionKey
        static let contextRoutingEnabled = false
        static let postProcessingProvider = PostProcessingProvider.openRouter.rawValue
        static let postProcessingModelOpenAI = "gpt-4o-mini"
        static let postProcessingModelGroq = "llama-3.1-8b-instant"
        static let customEndpointURL = ""
        static let customEndpointModel = ""
    }

    /// Register baseline defaults so first-run reads return sensible values
    /// instead of false/empty. Call exactly once at launch.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.provider: Defaults.provider,
            Key.modelOpenAI: Defaults.modelOpenAI,
            Key.modelOpenRouter: Defaults.modelOpenRouter,
            Key.modelGroq: Defaults.modelGroq,
            Key.localWhisperBinaryPath: Defaults.localWhisperBinaryPath,
            Key.localWhisperModelPath: Defaults.localWhisperModelPath,
            Key.language: Defaults.language,
            Key.autoPaste: Defaults.autoPaste,
            Key.sounds: Defaults.sounds,
            Key.indicatorStyle: Defaults.indicatorStyle,
            Key.postProcessingEnabled: Defaults.postProcessingEnabled,
            Key.postProcessingPreset: Defaults.postProcessingPreset,
            Key.postProcessingCustomPrompt: Defaults.postProcessingCustomPrompt,
            Key.postProcessingModel: Defaults.postProcessingModel,
            Key.historyEnabled: Defaults.historyEnabled,
            Key.historyRetentionDays: Defaults.historyRetentionDays,
            Key.historyMaxEntries: Defaults.historyMaxEntries,
            Key.audioRetention: Defaults.audioRetention,
            Key.fnKeyEnabled: Defaults.fnKeyEnabled,
            Key.hotkeyKeyCode: Defaults.hotkeyKeyCode,
            Key.hotkeyModifiers: Defaults.hotkeyModifiers,
            Key.contextRoutingEnabled: Defaults.contextRoutingEnabled,
            Key.postProcessingProvider: Defaults.postProcessingProvider,
            Key.postProcessingModelOpenAI: Defaults.postProcessingModelOpenAI,
            Key.postProcessingModelGroq: Defaults.postProcessingModelGroq,
            Key.customEndpointURL: Defaults.customEndpointURL,
            Key.customEndpointModel: Defaults.customEndpointModel
        ])
    }

    // MARK: - Available models

    struct AvailableModel: Identifiable, Hashable {
        let id: String
        let displayName: String
    }

    static let availableOpenAIModels: [AvailableModel] = [
        AvailableModel(id: "gpt-4o-mini-transcribe", displayName: "GPT-4o Mini Transcribe"),
        AvailableModel(id: "gpt-4o-transcribe", displayName: "GPT-4o Transcribe"),
        AvailableModel(id: "whisper-1", displayName: "Whisper-1")
    ]

    static let availableOpenRouterModels: [AvailableModel] = [
        AvailableModel(id: "openai/gpt-4o-audio-preview", displayName: "OpenAI GPT-4o Audio Preview"),
        AvailableModel(id: "openai/gpt-audio-mini", displayName: "OpenAI GPT Audio Mini")
    ]

    static let availableGroqModels: [AvailableModel] = [
        AvailableModel(id: "whisper-large-v3-turbo", displayName: "Whisper large-v3 Turbo"),
        AvailableModel(id: "whisper-large-v3", displayName: "Whisper large-v3"),
        AvailableModel(id: "distil-whisper-large-v3-en", displayName: "Distil Whisper large-v3 (English)")
    ]

    static var availableOpenAIModelIDs: Set<String> {
        Set(availableOpenAIModels.map(\.id))
    }

    static var availableOpenRouterModelIDs: Set<String> {
        Set(availableOpenRouterModels.map(\.id))
    }

    static var availableGroqModelIDs: Set<String> {
        Set(availableGroqModels.map(\.id))
    }

    // MARK: - Typed accessors (for non-SwiftUI consumers)

    static var provider: TranscriptionProvider {
        let raw = UserDefaults.standard.string(forKey: Key.provider) ?? Defaults.provider
        return TranscriptionProvider(rawValue: raw) ?? .openai
    }

    static var modelOpenAI: String {
        let raw = UserDefaults.standard.string(forKey: Key.modelOpenAI) ?? Defaults.modelOpenAI
        return availableOpenAIModelIDs.contains(raw) ? raw : Defaults.modelOpenAI
    }

    static var modelOpenRouter: String {
        let raw = UserDefaults.standard.string(forKey: Key.modelOpenRouter) ?? Defaults.modelOpenRouter
        return availableOpenRouterModelIDs.contains(raw) ? raw : Defaults.modelOpenRouter
    }

    static var modelGroq: String {
        let raw = UserDefaults.standard.string(forKey: Key.modelGroq) ?? Defaults.modelGroq
        return availableGroqModelIDs.contains(raw) ? raw : Defaults.modelGroq
    }

    static var localWhisperBinaryPath: String {
        UserDefaults.standard.string(forKey: Key.localWhisperBinaryPath) ?? Defaults.localWhisperBinaryPath
    }

    static var localWhisperModelPath: String {
        UserDefaults.standard.string(forKey: Key.localWhisperModelPath) ?? Defaults.localWhisperModelPath
    }

    /// Returns the model string for the currently-selected provider.
    /// For local whisper this is the model file's basename, computed by
    /// the provider itself at transcription time.
    static var currentModel: String {
        switch provider {
        case .openai: return modelOpenAI
        case .openRouter: return modelOpenRouter
        case .groq: return modelGroq
        case .polzaAI: return modelOpenAI  // Polza.ai uses OpenAI model names
        case .localWhisper:
            let name = URL(fileURLWithPath: localWhisperModelPath).lastPathComponent
            return name.isEmpty ? "local" : "local/\(name)"
        }
    }

    static var language: TranscriptionLanguage {
        let raw = UserDefaults.standard.string(forKey: Key.language) ?? Defaults.language
        return TranscriptionLanguage(rawValue: raw) ?? .auto
    }

    static var autoPaste: Bool {
        UserDefaults.standard.bool(forKey: Key.autoPaste)
    }

    static var sounds: Bool {
        UserDefaults.standard.bool(forKey: Key.sounds)
    }

    static var indicatorStyle: IndicatorStyle {
        let raw = UserDefaults.standard.string(forKey: Key.indicatorStyle) ?? Defaults.indicatorStyle
        return IndicatorStyle(rawValue: raw) ?? .menubar
    }

    // MARK: - Post-processing accessors

    static var postProcessingEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.postProcessingEnabled)
    }

    static var postProcessingPreset: PostProcessingPreset {
        let raw = UserDefaults.standard.string(forKey: Key.postProcessingPreset) ?? Defaults.postProcessingPreset
        return PostProcessingPreset(rawValue: raw) ?? .cleanup
    }

    static var postProcessingCustomPrompt: String {
        UserDefaults.standard.string(forKey: Key.postProcessingCustomPrompt) ?? Defaults.postProcessingCustomPrompt
    }

    static var postProcessingModel: String {
        UserDefaults.standard.string(forKey: Key.postProcessingModel) ?? Defaults.postProcessingModel
    }

    static var ppProvider: PostProcessingProvider {
        let raw = UserDefaults.standard.string(forKey: Key.postProcessingProvider) ?? Defaults.postProcessingProvider
        return PostProcessingProvider(rawValue: raw) ?? .openRouter
    }

    static var postProcessingModelOpenAI: String {
        UserDefaults.standard.string(forKey: Key.postProcessingModelOpenAI) ?? Defaults.postProcessingModelOpenAI
    }

    static var postProcessingModelGroq: String {
        UserDefaults.standard.string(forKey: Key.postProcessingModelGroq) ?? Defaults.postProcessingModelGroq
    }

    static var customEndpointURL: String {
        UserDefaults.standard.string(forKey: Key.customEndpointURL) ?? Defaults.customEndpointURL
    }

    static var customEndpointModel: String {
        UserDefaults.standard.string(forKey: Key.customEndpointModel) ?? Defaults.customEndpointModel
    }

    /// The model string for the currently selected post-processing provider.
    static var currentPostProcessingModel: String {
        switch ppProvider {
        case .openRouter: return postProcessingModel     // legacy key, OpenRouter namespace
        case .openAI: return postProcessingModelOpenAI
        case .groq: return postProcessingModelGroq
        case .polzaAI: return postProcessingModel        // same OpenAI-compatible namespace
        case .custom: return customEndpointModel
        }
    }

    /// Snapshots the current post-processing configuration into a Sendable
    /// struct so it can be handed off to a detached task without capturing
    /// UserDefaults lookups.
    static var currentPostProcessingOptions: PostProcessingOptions {
        PostProcessingOptions(
            preset: postProcessingPreset,
            customPrompt: postProcessingCustomPrompt,
            model: currentPostProcessingModel
        )
    }

    // MARK: - History accessors

    static var historyEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.historyEnabled)
    }

    static var historyRetentionDays: Int {
        let raw = UserDefaults.standard.integer(forKey: Key.historyRetentionDays)
        return max(0, raw)
    }

    static var historyMaxEntries: Int {
        let raw = UserDefaults.standard.integer(forKey: Key.historyMaxEntries)
        return raw > 0 ? raw : Defaults.historyMaxEntries
    }

    // MARK: - Audio retention

    static var audioRetention: AudioRetention {
        let raw = UserDefaults.standard.string(forKey: Key.audioRetention) ?? Defaults.audioRetention
        return AudioRetention(rawValue: raw) ?? .immediate
    }

    static var fnKeyEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.fnKeyEnabled)
    }

    // MARK: - Context routing

    static var contextRoutingEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.contextRoutingEnabled)
    }

    /// The user's context routing rules, decoded from JSON in UserDefaults.
    /// Falls back to the built-in defaults if nothing is saved yet.
    static var contextRules: [ContextRule] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Key.contextRules) else {
                return ContextRule.defaults
            }
            do {
                return try JSONDecoder().decode([ContextRule].self, from: data)
            } catch {
                NSLog("WhisperHot: failed to decode context rules → \(error.localizedDescription)")
                return ContextRule.defaults
            }
        }
        set {
            do {
                let data = try JSONEncoder().encode(newValue)
                UserDefaults.standard.set(data, forKey: Key.contextRules)
            } catch {
                NSLog("WhisperHot: failed to encode context rules → \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Hotkey

    /// Virtual key code for the Carbon hotkey. `kVK_ANSI_A == 0`, so we can't
    /// use "zero means unset" semantics here — `registerDefaults()` guarantees
    /// this is always populated on first read.
    static var hotkeyKeyCode: Int {
        UserDefaults.standard.integer(forKey: Key.hotkeyKeyCode)
    }

    /// Carbon modifier mask (cmdKey | optionKey | …). A zero mask is invalid
    /// for a global hotkey (would let a lone keypress fire anywhere), so we
    /// substitute the default.
    static var hotkeyModifiers: Int {
        let raw = UserDefaults.standard.integer(forKey: Key.hotkeyModifiers)
        return raw == 0 ? Defaults.hotkeyModifiers : raw
    }

    static var hotkeyCombo: HotkeyManager.Combo {
        HotkeyManager.Combo(
            keyCode: UInt32(hotkeyKeyCode),
            modifiers: UInt32(hotkeyModifiers)
        )
    }
}

/// Policy for how long raw WAV files linger in ~/Library/Caches/WhisperHot/
/// after the transcription request that produced them. Audio files can
/// contain anything the user said, so the default is `.immediate`.
enum AudioRetention: String, CaseIterable, Identifiable, Sendable {
    /// Delete as soon as a successful transcription returns. On failure,
    /// the file is kept so the user (or a startup sweep) can retry — but
    /// no longer than `.oneHour`.
    case immediate
    case oneHour
    case oneDay
    case untilQuit
    case forever

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .immediate: return "Delete immediately after transcription (recommended)"
        case .oneHour: return "Keep for 1 hour"
        case .oneDay: return "Keep for 24 hours"
        case .untilQuit: return "Keep until WhisperHot quits (best-effort; skipped on force-quit / crash)"
        case .forever: return "Keep forever"
        }
    }

    /// Max age for startup sweep. `nil` means "no age-based sweep" —
    /// either nothing to do (forever) or handled at quit (untilQuit).
    var sweepMaxAgeSeconds: TimeInterval? {
        switch self {
        case .immediate: return 3600            // stragglers from failed runs
        case .oneHour: return 3600
        case .oneDay: return 86_400
        case .untilQuit: return nil
        case .forever: return nil
        }
    }
}

/// Recording indicator style. Block 9 renders the actual UI for each;
/// Block 8 persists the choice.
enum IndicatorStyle: String, CaseIterable, Identifiable {
    case menubar
    case pill
    case waveform
    case floatingCapsule

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .menubar: return "Menubar only"
        case .pill: return "Mini (pill)"
        case .waveform: return "Classic (waveform)"
        case .floatingCapsule: return "Floating capsule (premium)"
        }
    }
}

/// The LLM provider used for post-processing (text cleanup, context routing).
/// Separate from the STT transcription provider.
enum PostProcessingProvider: String, CaseIterable, Identifiable {
    case openRouter = "openrouter"
    case openAI = "openai"
    case groq = "groq"
    case polzaAI = "polzaai"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .openAI: return "OpenAI"
        case .groq: return "Groq"
        case .polzaAI: return "Polza.ai"
        case .custom: return "Custom endpoint"
        }
    }

    var keychainAccount: Keychain.Account {
        switch self {
        case .openRouter: return .openRouter
        case .openAI: return .openAI
        case .groq: return .groq
        case .polzaAI: return .polzaAI
        case .custom: return .customEndpoint
        }
    }

    /// Returns the endpoint URL, or nil if the custom endpoint URL is invalid/empty.
    /// Callers must handle nil by skipping post-processing or showing an error.
    var endpoint: URL? {
        switch self {
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        case .openAI: return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .groq: return URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        case .polzaAI: return URL(string: "https://polza.ai/api/v1/chat/completions")!
        case .custom:
            let raw = Preferences.customEndpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, let url = URL(string: raw), url.scheme == "https" || url.scheme == "http" else {
                return nil
            }
            return url
        }
    }

    var extraHeaders: [String: String] {
        switch self {
        case .openRouter:
            return [
                "HTTP-Referer": "https://github.com/LexorCrypto/whisper-hot",
                "X-Title": "WhisperHot"
            ]
        case .openAI, .groq, .polzaAI, .custom:
            return [:]
        }
    }
}

/// The STT provider the user has currently selected.
enum TranscriptionProvider: String, CaseIterable, Identifiable {
    case openai
    case openRouter = "openrouter"
    case groq
    case polzaAI = "polzaai"
    case localWhisper = "localwhisper"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI (/audio/transcriptions)"
        case .openRouter: return "OpenRouter (chat with audio)"
        case .groq: return "Groq (/audio/transcriptions)"
        case .polzaAI: return "Polza.ai (OpenAI-совместимый, РФ)"
        case .localWhisper: return "Local whisper.cpp (fully offline)"
        }
    }

    var shortName: String {
        switch self {
        case .openai: return "OpenAI"
        case .openRouter: return "OpenRouter"
        case .groq: return "Groq"
        case .polzaAI: return "Polza.ai"
        case .localWhisper: return "Local"
        }
    }

    var keychainAccount: Keychain.Account? {
        switch self {
        case .openai: return .openAI
        case .openRouter: return .openRouter
        case .groq: return .groq
        case .polzaAI: return .polzaAI
        case .localWhisper: return nil
        }
    }
}
