import Foundation

/// Supported UI languages. Stored in UserDefaults.
enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case ru

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        }
    }
}

/// Simple localization lookup. All UI strings live here.
/// Usage: `L10n.settings` returns the localized string for the current language.
enum L10n {
    static var lang: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: Preferences.Key.appLanguage) ?? Preferences.Defaults.appLanguage
        return AppLanguage(rawValue: raw) ?? .ru
    }

    // MARK: - Settings sections
    static var recording: String { lang == .ru ? "Запись" : "Recording" }
    static var providers: String { lang == .ru ? "Провайдеры" : "Providers" }
    static var postProcessing: String { lang == .ru ? "Обработка" : "Post-processing" }
    static var hotkey: String { lang == .ru ? "Горячие клавиши" : "Hotkey" }
    static var historyPrivacy: String { lang == .ru ? "История и приватность" : "History & Privacy" }

    // MARK: - Recording tab
    static var language: String { lang == .ru ? "Язык" : "Language" }
    static var languageHint: String { lang == .ru ? "Передаётся провайдеру как подсказка. Авто-определение использует встроенный детектор провайдера." : "Passed to every provider as a language hint. Auto-detect uses the provider's own detection." }
    static var afterTranscription: String { lang == .ru ? "После транскрипции" : "After transcription" }
    static var autoPasteToggle: String { lang == .ru ? "Автоматически вставлять в активное приложение" : "Auto-paste into the active app" }
    static var soundChimesToggle: String { lang == .ru ? "Звуковые сигналы" : "Play sound chimes" }
    static var autoPasteHint: String { lang == .ru ? "Для авто-вставки нужно разрешение Accessibility. Если текст не вставляется, откройте Системные настройки → Конфиденциальность → Универсальный доступ и включите WhisperHot." : "Auto-paste requires Accessibility permission. If nothing pastes, open System Settings → Privacy & Security → Accessibility and re-enable WhisperHot." }
    static var indicator: String { lang == .ru ? "Индикатор" : "Indicator" }
    static var style: String { lang == .ru ? "Стиль" : "Style" }
    static var startup: String { lang == .ru ? "Автозапуск" : "Startup" }
    static var launchAtLogin: String { lang == .ru ? "Запускать при входе в систему" : "Launch at login" }
    static var interfaceLanguage: String { lang == .ru ? "Язык интерфейса" : "Interface language" }

    // MARK: - Providers tab
    static var service: String { lang == .ru ? "Сервис" : "Service" }
    static var provider: String { lang == .ru ? "Провайдер" : "Provider" }
    static var apiKey: String { lang == .ru ? "API-ключ" : "API Key" }
    static var model: String { lang == .ru ? "Модель" : "Model" }
    static var save: String { lang == .ru ? "Сохранить" : "Save" }
    static var delete: String { lang == .ru ? "Удалить" : "Delete" }
    static var savedToKeychain: String { lang == .ru ? "Сохранено в Keychain." : "Saved to Keychain." }
    static var deletedFromKeychain: String { lang == .ru ? "Удалено из Keychain." : "Deleted from Keychain." }
    static var keyIsEmpty: String { lang == .ru ? "Ключ пустой." : "Key is empty." }
    static var noKeySaved: String { lang == .ru ? "Ключ не сохранён." : "No key saved yet." }
    static var loadedFromKeychain: String { lang == .ru ? "Загружен из Keychain." : "Loaded from Keychain." }
    static var choose: String { lang == .ru ? "Выбрать…" : "Choose…" }
    static var clear: String { lang == .ru ? "Очистить" : "Clear" }
    static var binary: String { lang == .ru ? "Бинарный файл" : "Binary" }
    static var ggmlModel: String { lang == .ru ? "GGML модель" : "GGML model" }
    static var localWhisperHint: String { lang == .ru ? "Установите через Homebrew (`brew install whisper-cpp`) или соберите из исходников, затем скачайте GGML модель с huggingface.co/ggerganov/whisper.cpp." : "Install via Homebrew (`brew install whisper-cpp`) or build from source, then download a GGML model from huggingface.co/ggerganov/whisper.cpp." }
    static var notSet: String { lang == .ru ? "не задано" : "not set" }

    // MARK: - Post-processing tab
    static var llmCleanup: String { lang == .ru ? "LLM-обработка" : "LLM cleanup" }
    static var llmCleanupToggle: String { lang == .ru ? "Обрабатывать текст через LLM после транскрипции" : "Run LLM cleanup after transcription" }
    static var llmCleanupHint: String { lang == .ru ? "Отправляет транскрипт через LLM для очистки филлеров, стилизации или перевода. Одно дополнительное обращение к API на запись. Совет: нажмите ⌥⌘⇧5 вместо ⌥⌘5 для вставки без обработки." : "Sends the raw transcript through an LLM to clean fillers, rewrite for tone, or translate. Costs one extra API call per recording. Tip: press ⌥⌘⇧5 instead of ⌥⌘5 to skip cleanup and paste raw text." }
    static var ppProvider: String { lang == .ru ? "Провайдер обработки" : "Post-processing provider" }
    static var preset: String { lang == .ru ? "Пресет" : "Preset" }
    static var customSystemPrompt: String { lang == .ru ? "Пользовательский системный промпт" : "Custom system prompt" }
    static var contextRouting: String { lang == .ru ? "Контекстный роутинг" : "Context routing" }
    static var contextRoutingToggle: String { lang == .ru ? "Автовыбор пресета по активному приложению" : "Auto-select preset based on active app" }
    static var contextRoutingHint: String { lang == .ru ? "Пресет подбирается автоматически по приложению, в которое вы диктуете (Slack = казуально, Mail = формально). Правила настраиваются ниже." : "When enabled, the preset is chosen automatically based on the app you're dictating into (e.g. Slack = casual, Mail = formal). You can customize the rules below." }
    static var addRule: String { lang == .ru ? "Добавить правило…" : "Add rule..." }
    static var resetToDefaults: String { lang == .ru ? "Сбросить по умолчанию" : "Reset to defaults" }
    static var bundleIDTip: String { lang == .ru ? "Совет: чтобы узнать bundle ID приложения, выполните в Терминале: osascript -e 'id of app \"Имя\"'" : "Tip: to find an app's bundle ID, run in Terminal: osascript -e 'id of app \"AppName\"'" }

    // MARK: - Hotkey tab
    static var recordStop: String { lang == .ru ? "Запись / Стоп" : "Record / Stop" }
    static var shortcut: String { lang == .ru ? "Сочетание клавиш" : "Shortcut" }
    static var reset: String { lang == .ru ? "Сбросить" : "Reset" }
    static var fnKeyExperimental: String { lang == .ru ? "Клавиша Fn (экспериментально)" : "Fn key (experimental)" }
    static var useFnKey: String { lang == .ru ? "Использовать Fn (🌐) вместо хоткея" : "Use Fn (🌐) key instead" }
    static var hotkeyActiveHint: String { lang == .ru ? "Нажмите на поле и введите новую комбинацию. Нужен хотя бы один модификатор (⌘/⌥/⌃/⇧). Esc для отмены." : "Click the field and press a new combo. Requires at least one modifier (⌘/⌥/⌃/⇧). Press ⎋ to cancel." }
    static var fnActiveHint: String { lang == .ru ? "Fn (🌐) активна — комбинация выше отключена. Выключите Fn чтобы использовать обычный хоткей." : "The Fn (🌐) transport is active — the combo above is disabled. Turn off the Fn toggle below to use a regular key combo." }

    // MARK: - History & Privacy tab
    static var transcriptHistory: String { lang == .ru ? "История транскриптов" : "Transcript history" }
    static var keepLocalHistory: String { lang == .ru ? "Хранить локальную историю" : "Keep a local history" }
    static var retention: String { lang == .ru ? "Хранение" : "Retention" }
    static var keepForever: String { lang == .ru ? "Хранить бессрочно" : "Keep forever" }
    static var maxEntries: String { lang == .ru ? "Макс. записей" : "Max entries" }
    static var historyEncryptionHint: String { lang == .ru ? "История зашифрована AES-GCM. Ключ хранится в macOS Keychain и не синхронизируется в iCloud." : "History is encrypted at rest with AES-GCM. The key lives in the macOS Keychain and never syncs to iCloud." }
    static var audioRetention: String { lang == .ru ? "Хранение аудио" : "Audio retention" }
    static var keepRecordings: String { lang == .ru ? "Хранить записи" : "Keep recordings" }
    static var wipeAllAudio: String { lang == .ru ? "Удалить все аудиозаписи" : "Wipe all recorded audio now" }
    static var privacyNotes: String { lang == .ru ? "Заметки о приватности" : "Privacy notes" }
    static var privacyCloud: String { lang == .ru ? "Облачные провайдеры (OpenAI, OpenRouter, Groq, Polza.ai) получают ваше аудио. Выберите Local whisper.cpp для полностью офлайн транскрипции." : "Cloud providers (OpenAI, OpenRouter, Groq, Polza.ai) receive your audio. Pick Local whisper.cpp in Providers for fully offline transcription." }
    static var privacyClipboard: String { lang == .ru ? "Менеджеры буфера обмена (Paste, Raycast, Alfred) захватят транскрипт. Отключите авто-вставку если это важно." : "Clipboard managers (Paste, Raycast, Alfred) will capture the transcript when it reaches the pasteboard. Disable auto-paste in Recording if that concerns you." }
    static var privacyFiles: String { lang == .ru ? "WAV файлы хранятся в ~/Library/Caches/WhisperHot/recordings/. API-ключи и ключ шифрования в macOS Keychain (iCloud синхронизация отключена)." : "Raw WAVs live in ~/Library/Caches/WhisperHot/recordings/. API keys and the history encryption key are in the macOS Keychain with iCloud sync disabled." }

    // MARK: - Menu items
    static var startRecording: String { lang == .ru ? "Начать запись" : "Start Recording" }
    static var stopRecording: String { lang == .ru ? "Остановить запись" : "Stop Recording" }
    static var transcribing: String { lang == .ru ? "Транскрибация…" : "Transcribing…" }
    static var settings: String { lang == .ru ? "Настройки…" : "Settings…" }
    static var openWhisperHot: String { lang == .ru ? "Открыть WhisperHot" : "Open WhisperHot" }
    static var history: String { lang == .ru ? "История" : "History" }
    static var about: String { lang == .ru ? "О WhisperHot" : "About WhisperHot" }
    static var permissions: String { lang == .ru ? "Разрешения и настройка…" : "Permissions & Onboarding…" }
    static var quit: String { lang == .ru ? "Завершить WhisperHot" : "Quit WhisperHot" }
    static var autoOfflineOnTimeout: String { lang == .ru ? "Авто-переключение на Offline при медленной сети" : "Auto-switch to Offline when slow" }
    static var stop: String { lang == .ru ? "Стоп" : "Stop" }

    // MARK: - Main window
    static var mainGroupOverview: String { lang == .ru ? "Обзор" : "Overview" }
    static var mainGroupSettings: String { lang == .ru ? "Настройки" : "Settings" }
    static var mainGroupData: String { lang == .ru ? "Данные и доступ" : "Data & Access" }
    static var mainDashboard: String { lang == .ru ? "Главная" : "Dashboard" }
    static var mainPrivacySettings: String { lang == .ru ? "Приватность" : "Privacy" }
    static var mainSetup: String { lang == .ru ? "Настройка" : "Setup" }
    static var mainFirstRunReady: String { lang == .ru ? "Можно записывать" : "Ready to record" }
    static var mainFirstRunNeedsAttention: String { lang == .ru ? "Осталось закончить настройку" : "Finish setup to record" }
    static var mainStatusReady: String { lang == .ru ? "Готов к записи" : "Ready to record" }
    static var mainStatusRecording: String { lang == .ru ? "Идёт запись" : "Recording" }
    static var mainStatusTranscribing: String { lang == .ru ? "Транскрибирую" : "Transcribing" }
    static var mainCurrentRoute: String { lang == .ru ? "Текущий маршрут" : "Current route" }
    static var mainWritingPipeline: String { lang == .ru ? "Пайплайн текста" : "Writing pipeline" }
    static var mainLocalFallback: String { lang == .ru ? "Локальный fallback" : "Local fallback" }
    static var mainPostProcessingOn: String { lang == .ru ? "LLM-обработка включена" : "LLM cleanup on" }
    static var mainPostProcessingOff: String { lang == .ru ? "LLM-обработка выключена" : "LLM cleanup off" }
    static var mainContextRoutingOn: String { lang == .ru ? "Контекстный роутинг включён" : "Context routing on" }
    static var mainContextRoutingOff: String { lang == .ru ? "Контекстный роутинг выключен" : "Context routing off" }
    static var mainHistoryOn: String { lang == .ru ? "История включена" : "History on" }
    static var mainHistoryOff: String { lang == .ru ? "История выключена" : "History off" }
    static var mainAutoPasteOn: String { lang == .ru ? "Авто-вставка включена" : "Auto-paste on" }
    static var mainAutoPasteOff: String { lang == .ru ? "Авто-вставка выключена" : "Auto-paste off" }
    static var mainLocalReady: String { lang == .ru ? "Local whisper.cpp готов" : "Local whisper.cpp ready" }
    static var mainLocalNotReady: String { lang == .ru ? "Local whisper.cpp не настроен" : "Local whisper.cpp not set up" }
    static var mainAutoOfflineOn: String { lang == .ru ? "Авто-offline при медленной сети включён" : "Auto-offline on slow network" }
    static var mainAutoOfflineOff: String { lang == .ru ? "Авто-offline при медленной сети выключен" : "Auto-offline disabled" }
    static var mainOpenSettings: String { lang == .ru ? "Открыть настройки" : "Open Settings" }
    static var mainConfigureProviders: String { lang == .ru ? "Настроить провайдеры" : "Configure Providers" }
    static var mainViewHistory: String { lang == .ru ? "Посмотреть историю" : "View History" }
    static var mainOpenSetup: String { lang == .ru ? "Открыть настройку доступа" : "Open Setup" }
    static var mainOpenProviders: String { lang == .ru ? "Открыть провайдеры" : "Open Providers" }
    static var mainOpenHistoryWindow: String { lang == .ru ? "Открыть историю окном" : "Open History Window" }
    static var mainOpenPermissionsWindow: String { lang == .ru ? "Открыть разрешения окном" : "Open Permissions Window" }
    static var mainPermissionsReady: String { lang == .ru ? "Разрешения готовы" : "Permissions ready" }
    static var mainPermissionsNeedAttention: String { lang == .ru ? "Нужно настроить разрешения" : "Permissions need attention" }
    static var mainMicPermission: String { lang == .ru ? "Микрофон" : "Microphone" }
    static var mainAccessibilityPermission: String { lang == .ru ? "Accessibility" : "Accessibility" }
    static var mainInputMonitoringPermission: String { lang == .ru ? "Input Monitoring" : "Input Monitoring" }
    static var mainGranted: String { lang == .ru ? "Разрешено" : "Granted" }
    static var mainNotGranted: String { lang == .ru ? "Не разрешено" : "Not granted" }
    static var mainDenied: String { lang == .ru ? "Запрещено" : "Denied" }
    static var mainNotRequested: String { lang == .ru ? "Не запрошено" : "Not requested" }
    static var mainRequestAccess: String { lang == .ru ? "Запросить доступ" : "Request Access" }
    static var mainOpenSystemSettings: String { lang == .ru ? "Открыть системные настройки" : "Open System Settings" }
    static var mainReadyPill: String { lang == .ru ? "Готово" : "Ready" }
    static var mainProviderNoKeyRequired: String { lang == .ru ? "API-ключ не нужен." : "No API key required." }
    static var mainProviderKeyCheckDeferred: String {
        lang == .ru
            ? "Ключ не читается при запуске, чтобы не вызывать Keychain prompt."
            : "Key is not read at launch to avoid Keychain prompts."
    }
    static var mainLocalProviderMissingDetail: String {
        lang == .ru
            ? "Укажите binary и GGML модель в Providers."
            : "Choose the binary and GGML model in Providers."
    }
    static func mainProviderReady(_ provider: String) -> String {
        lang == .ru ? "\(provider) готов" : "\(provider) ready"
    }
    static func mainProviderNotChecked(_ provider: String) -> String {
        lang == .ru ? "\(provider) не проверяется при запуске" : "\(provider) not checked at launch"
    }
    static func mainProviderNeedsSetup(_ provider: String) -> String {
        lang == .ru ? "Нужно настроить \(provider)" : "Set up \(provider)"
    }
    static func mainProviderNeedsAPIKey(_ provider: String) -> String {
        lang == .ru ? "Нужен API-ключ \(provider)" : "\(provider) API key needed"
    }
    static func mainProviderMissingKeyDetail(_ provider: String) -> String {
        lang == .ru
            ? "Сохраните ключ \(provider) в Providers."
            : "Save the \(provider) key in Providers."
    }
    static func mainProviderKeySavedDetail(_ provider: String) -> String {
        lang == .ru
            ? "Ключ \(provider) сохранён в Keychain."
            : "\(provider) key is saved in Keychain."
    }
    static func mainLocalProviderReady(_ model: String) -> String {
        lang == .ru ? "Модель: \(model)" : "Model: \(model)"
    }
    static func mainProviderCheckFailed(_ provider: String) -> String {
        lang == .ru ? "Не удалось проверить \(provider)" : "Could not check \(provider)"
    }

    // MARK: - Recording / transcription banners (status menu)
    static func recordingErrorBanner(_ message: String) -> String {
        lang == .ru ? "⚠ Ошибка записи: \(message)" : "⚠ Recording error: \(message)"
    }
    static func transcriptionErrorBanner(_ message: String) -> String {
        lang == .ru ? "⚠ Ошибка транскрипции: \(message)" : "⚠ Transcription error: \(message)"
    }
    static var offlineFallbackBanner: String {
        lang == .ru
            ? "⚡ Использована локальная транскрипция (нет интернета)"
            : "⚡ Used local transcription (offline)"
    }
    static var autoOfflineNeedsLocalWhisperTooltip: String {
        lang == .ru
            ? "Сначала настрой Local whisper.cpp в Settings → Providers"
            : "Set up Local whisper.cpp in Settings → Providers first"
    }

    // MARK: - Settings sections (additional)
    static var sectionUpdates: String { lang == .ru ? "Обновления" : "Updates" }
    static var sectionAbout: String { lang == .ru ? "О приложении" : "About" }
    static var sectionVersion: String { lang == .ru ? "Версия" : "Version" }
    static var sectionCloudProvider: String { lang == .ru ? "Облачный провайдер" : "Cloud provider" }
    static var technicalVocabulary: String { lang == .ru ? "Технический словарь" : "Technical vocabulary" }
    static var recognitionHints: String { lang == .ru ? "Подсказки для распознавания" : "Recognition hints" }
    static var recognitionHintsHelp: String {
        lang == .ru
            ? "Через запятую. Передаются провайдеру как подсказка для лучшего распознавания технических терминов."
            : "Comma-separated. Passed to the STT provider as hints for better recognition of technical terms."
    }
    static var addReplacement: String { lang == .ru ? "Добавить замену" : "Add replacement" }
    static var wordReplacementsHelp: String {
        lang == .ru
            ? "Замены применяются к тексту сразу после транскрипции (до LLM-обработки). Регистр не учитывается."
            : "Replacements are applied right after transcription (before LLM processing). Case-insensitive."
    }

    // MARK: - Local whisper installer
    static var useLocalTranscription: String {
        lang == .ru ? "Использовать локальную транскрипцию" : "Use local transcription"
    }
    static var installerInstalled: String { lang == .ru ? "Установлено" : "Installed" }
    static var installerNotInstalled: String { lang == .ru ? "Не установлено" : "Not installed" }
    static var installerInstall: String { lang == .ru ? "Установить" : "Install" }
    static var installerCancel: String { lang == .ru ? "Отмена" : "Cancel" }
    static var manualPathConfiguration: String {
        lang == .ru ? "Ручная настройка путей" : "Manual path configuration"
    }
    static var localWhisperInstallHelp: String {
        lang == .ru
            ? "Нажмите «Установить» для автоматической установки whisper-cpp через Homebrew и загрузки модели ggml-base (~142 МБ). Установка занимает 2-5 минут. Или настройте пути вручную."
            : "Click Install to automatically set up whisper-cpp via Homebrew and download the ggml-base model (~142 MB). Installation takes 2-5 minutes. Or configure paths manually."
    }
    static var homebrewNotFound: String {
        lang == .ru
            ? "Homebrew не найден. Установите (2-5 мин): /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            : "Homebrew not found. Install (2-5 min): /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    }
    static var installingWhisperViaBrew: String {
        lang == .ru
            ? "Установка whisper-cpp через Homebrew (2-5 мин)..."
            : "Installing whisper-cpp via Homebrew (2-5 min)..."
    }
    static var installFinishedFilesMissing: String {
        lang == .ru
            ? "Установка завершена, но файлы не найдены"
            : "Installation finished but files not found"
    }

    // MARK: - Local LLM (post-processing)
    static var llamaCliPath: String { lang == .ru ? "Путь к llama-cli" : "llama-cli path" }
    static var ggufModelPath: String { lang == .ru ? "Путь к GGUF модели" : "GGUF model path" }
    static var localLLMHelp: String {
        lang == .ru
            ? "Полностью офлайн обработка. Установите llama.cpp: brew install llama.cpp. Скачайте GGUF модель с huggingface.co."
            : "Fully offline processing. Install: brew install llama.cpp. Download a GGUF model from huggingface.co."
    }

    // MARK: - Custom endpoint validation
    static var invalidHttpsURL: String {
        lang == .ru
            ? "Неверный URL. Должен начинаться с https://"
            : "Invalid URL. Must start with https://"
    }

    // MARK: - Updates
    static var currentVersionLabel: String { lang == .ru ? "Текущая версия:" : "Current version:" }
    static var checkingUpdates: String { lang == .ru ? "Проверяю..." : "Checking..." }
    static func upToDateMessage(_ version: String) -> String {
        lang == .ru
            ? "Вы используете последнюю версию (\(version))"
            : "You're on the latest version (\(version))"
    }
    static func updateAvailableMessage(latest: String, current: String) -> String {
        lang == .ru
            ? "Доступна версия \(latest) (у вас \(current))"
            : "Version \(latest) available (you have \(current))"
    }
    static var downloadUpdate: String {
        lang == .ru ? "Скачать обновление" : "Download update"
    }
    static var checkForUpdates: String {
        lang == .ru ? "Проверить обновления" : "Check for updates"
    }
    static var aboutAppDescription: String {
        lang == .ru
            ? "macOS приложение для голосовой транскрипции. Apple Silicon (M1+), macOS 13.0+."
            : "macOS speech-to-text app. Apple Silicon (M1+), macOS 13.0+."
    }
    static var githubRateLimitExceeded: String {
        lang == .ru
            ? "Превышен лимит запросов GitHub API. Попробуйте позже."
            : "GitHub API rate limit exceeded. Try again later."
    }

    // MARK: - Provider descriptions
    static func providerDescription(for p: TranscriptionProvider) -> String {
        switch p {
        case .openai:
            return lang == .ru
                ? "Специализированный STT-endpoint. Максимальная точность, самый дорогой."
                : "Dedicated STT endpoint. Most accurate, most expensive."
        case .openRouter:
            return lang == .ru
                ? "Маршрутизирует аудио в chat-модели через /chat/completions. Один ключ, много моделей."
                : "Routes audio to chat models like GPT-4o Audio Preview via /chat/completions. One key, many models."
        case .groq:
            return lang == .ru
                ? "OpenAI-совместимый STT. Whisper large-v3-turbo примерно в 10× быстрее и намного дешевле OpenAI."
                : "OpenAI-compatible STT mirror. Whisper large-v3-turbo is roughly 10× faster and much cheaper than OpenAI direct."
        case .polzaAI:
            return lang == .ru
                ? "Российский LLM-агрегатор. OpenAI-совместимый API, оплата российскими картами, 400+ моделей."
                : "Russian LLM aggregator. OpenAI-compatible API, Russian cards accepted, 400+ models."
        case .localWhisper:
            return lang == .ru
                ? "Запускает whisper.cpp на вашем Mac. Полностью офлайн, без API-ключа, без сети."
                : "Runs whisper.cpp on your Mac via subprocess. Fully offline, no API key, no network."
        }
    }

    // MARK: - Indicator styles
    static func indicatorStyleName(_ s: IndicatorStyle) -> String {
        switch s {
        case .menubar: return lang == .ru ? "Только менюбар" : "Menubar only"
        case .pill: return lang == .ru ? "Мини (пилюля)" : "Mini (pill)"
        case .waveform: return lang == .ru ? "Классика (волна)" : "Classic (waveform)"
        case .floatingCapsule: return lang == .ru ? "Плавающая капсула (premium)" : "Floating capsule (premium)"
        case .studio: return lang == .ru ? "Студия (широкая панель)" : "Studio (wide panel)"
        }
    }

    // MARK: - Audio retention policies
    static func audioRetentionName(_ r: AudioRetention) -> String {
        switch r {
        case .immediate:
            return lang == .ru
                ? "Удалять сразу после транскрипции (рекомендуется)"
                : "Delete immediately after transcription (recommended)"
        case .oneHour:
            return lang == .ru ? "Хранить 1 час" : "Keep for 1 hour"
        case .oneDay:
            return lang == .ru ? "Хранить 24 часа" : "Keep for 24 hours"
        case .untilQuit:
            return lang == .ru
                ? "Хранить до выхода из WhisperHot (по возможности; не сработает при принудительном завершении или сбое)"
                : "Keep until WhisperHot quits (best-effort; skipped on force-quit / crash)"
        case .forever:
            return lang == .ru ? "Хранить бессрочно" : "Keep forever"
        }
    }
}
