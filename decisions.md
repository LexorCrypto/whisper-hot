# WhisperHot — Журнал архитектурных решений (ADR Log)

> Документ фиксирует **почему** в проекте сделан тот или иной выбор. «Что» описано в `ARCHITECTURE.md`, «как использовать» — в `README.md` и `CLAUDE.md`. Здесь — мотивация.
>
> Формат записи: **Контекст → Решение → Обоснование → Последствия → Альтернативы**.
>
> Версия приложения на момент ревизии: **0.6.2**.
>
> Автор: Aleksei Supilin. Лицензия: Apache 2.0.

---

## ADR-001 — AppKit shell + SwiftUI content, не чистый SwiftUI

**Контекст.** macOS menu bar приложение, которое записывает голос, транскрибирует и вставляет текст в активное приложение. Нужен non-activating floating panel, сохранение фокуса, LSUIElement.

**Решение.** AppKit (`NSStatusItem`, `NSPanel`, `NSWindow`) для оболочки; SwiftUI внутри `NSHostingView` для Settings, Onboarding, History, индикаторов записи.

**Обоснование.**
- Recording indicator — non-activating `NSPanel` с `collectionBehavior` (.canJoinAllSpaces, .stationary, .fullScreenAuxiliary). MenuBarExtra это не даёт.
- Auto-paste требует, чтобы WhisperHot НИКОГДА не был frontmost во время транскрипции. `LSUIElement = true` + `NSStatusItem` — надёжная оболочка.
- Settings и Onboarding должны восстанавливать фокус на предыдущее приложение при закрытии. SwiftUI scenes агрессивно крадут фокус.

**Последствия.** Два мира (AppKit + SwiftUI) усложняют lifecycle. Компенсируется тем, что SwiftUI живёт только внутри hosting views.

**Альтернативы.** SwiftUI `MenuBarExtra` — отвергнут из-за отсутствия контроля над окнами и focus management.

---

## ADR-002 — Swift 5.9 / SwiftPM, zero external dependencies

**Контекст.** Персональный проект, замена SuperWhisper. Минимальная сложность сборки.

**Решение.** SwiftPM без внешних зависимостей. Все фреймворки — системные Apple (AppKit, SwiftUI, AVFoundation, CryptoKit, Security, Carbon).

**Обоснование.**
- Нет dependency hell. `swift build` работает сразу.
- Все API стабильны (Apple frameworks).
- Проект достаточно мал (~8500 LOC) чтобы не нуждаться в сторонних библиотеках.

**Последствия.** Некоторые вещи делаются вручную (HTTP клиент через URLSession, keychain через Security framework, hotkeys через Carbon). Приемлемо для данного масштаба.

**Альтернативы.** Alamofire, KeychainAccess, HotKey — отвергнуты ради zero dependencies.

---

## ADR-003 — Carbon RegisterEventHotKey для глобального хоткея

**Контекст.** Нужен глобальный хоткей, работающий из любого приложения. Два варианта: Carbon RegisterEventHotKey (legacy, но надёжный) или CGEventTap (flexible, но требует Input Monitoring).

**Решение.** Carbon `RegisterEventHotKey` как primary. CGEventTap — только для experimental Fn key. Два Carbon hotkey: primary (⌥⌘5) + raw output (⌥⌘⇧5).

**Обоснование.**
- Carbon hotkeys не требуют Accessibility или Input Monitoring permission.
- Доставляются синхронно на main thread — можно сразу захватить `frontmostApplication`.
- Два раздельных ID позволяют отличить обычную остановку от raw output (Shift variant).

**Последствия.**
- Carbon API deprecated, но работает на macOS 13+. Замена — CGEventTap (требует Input Monitoring).
- Если пользователь привяжет хоткей с Shift, raw output variant не регистрируется (guardrail).

**Альтернативы.** CGEventTap — используется только для Fn key (experimental). NSEvent.addGlobalMonitorForEvents — не подходит (не блокирует событие, не sync с main).

---

## ADR-004 — Context Router: bundle ID + window title (AX API)

**Контекст.** Нужно автоматически подбирать стиль пост-обработки по активному приложению (Slack = casual, Mail = formal).

**Решение.** `ContextRouter` сканирует rules по bundle ID. Для браузеров дополнительно читает window title через Accessibility API (`AXUIElementCopyAttributeValue`). Lazy query — AX вызывается только когда есть правило с `titleContains`.

**Обоснование.**
- Bundle ID доступен через `NSWorkspace.shared.frontmostApplication` без permission.
- Window title для браузеров позволяет различать Gmail/Slack/Telegram в одном Chrome.
- AX API graceful fallback — если Accessibility не выдан, просто не матчит title rules.

**Последствия.**
- Window title читается в момент resolve (после остановки записи), не в момент старта. Если пользователь переключил вкладку — может попасть не тот пресет.
- AX query — cross-process IPC, ~1-5ms. Lazy query минимизирует overhead.

**Альтернативы.** Скриншот экрана (Wispr Flow подход) — отвергнут из-за privacy. NSWorkspace.runningApplications — даёт только bundle ID, не title.

---

## ADR-005 — Мульти-провайдер: один LLMPostProcessor, параметризованный

**Контекст.** Пост-обработка поддерживает 6 провайдеров: OpenRouter, OpenAI, Groq, Polza.ai, Custom endpoint, Local LLM. Все кроме Local LLM используют одинаковый формат (chat completions).

**Решение.** Один класс `LLMPostProcessor` с `endpoint: URL`, `extraHeaders`, `apiKeyProvider` как init params. Для Local LLM — отдельный `LocalLLMProcessor` (subprocess llama-cli). Codex рекомендовал один класс вместо протокола + фабрики.

**Обоснование.**
- Формат идентичен для всех облачных провайдеров. Протокол — преждевременная абстракция.
- Минимальный diff при добавлении нового провайдера (только endpoint URL + model slug).

**Последствия.** Если какой-то провайдер изменит формат (не chat completions), придётся выделять отдельный класс. Маловероятно для OpenAI-compatible API.

**Альтернативы.** Протокол + N реализаций — отвергнут по рекомендации Codex (excessive abstraction).

---

## ADR-006 — FallbackTranscriptionService для offline

**Контекст.** Если облачный провайдер недоступен (нет интернета), нужно автоматически переключиться на локальный whisper.cpp.

**Решение.** `FallbackTranscriptionService` — wrapper, который ловит `URLError.notConnectedToInternet` и `.networkConnectionLost` от primary и ретраит через local fallback. НЕ ловит `.timedOut` (медленный провайдер ≠ offline).

**Обоснование.**
- Wrapper чище чем условная логика в MenuBarController (рекомендация Codex).
- `TranscriptionResult.usedOfflineFallback: Bool` позволяет пропустить пост-обработку (LLM тоже не работает без сети).

**Последствия.** Fallback срабатывает только на два конкретных URLError. HTTP 502/503 не триггерит fallback — это серверная проблема, не offline.

**Альтернативы.** NWPathMonitor precheck — рассматривался как дополнение, отложен.

---

## ADR-007 — TranscriptionCoordinator: извлечение из god object

**Контекст.** MenuBarController вырос до 984 строк. Содержал: UI, state machine, hotkeys, permissions, recording, transcription orchestration, paste, history, error presentation.

**Решение.** Выделен `TranscriptionCoordinator` — struct, инкапсулирует pipeline: provider selection → fallback → context routing → word replacements → post-processing. `fromPreferences()` снапшотит все настройки на main actor, `run()` выполняется off-main.

**Обоснование.**
- MenuBarController сократился до 828 строк (−16%).
- Coordinator тестируемый (Sendable struct, чистая функция).
- Factory pattern: всё снапшотится до начала async работы.

**Последствия.** Coordinator не видит UI — не может показывать баннеры. Это правильно (separation of concerns). UI-реакция — ответственность MenuBarController.

**Альтернативы.** MVVM с отдельным ViewModel — overkill для menu bar app. Coordinator достаточен.

---

## ADR-008 — Library target split (WhisperHotLib + executable + tests)

**Контекст.** SwiftPM не позволяет `@testable import` для `.executableTarget`. Тесты копировали production логику вместо тестирования реального кода.

**Решение.** 3 SwiftPM target: `WhisperHotLib` (.target), `WhisperHot` (.executableTarget, thin main.swift), `WhisperHotTests` (.testTarget). Только `Preferences` и `AppDelegate` сделаны `public`. Тесты используют `@testable import WhisperHotLib`.

**Обоснование.**
- Тесты теперь работают с реальным production кодом (ContextRule, WordReplacement, PostProcessingPreset).
- Минимальный public surface: только 2 типа для executable, всё остальное internal.

**Последствия.** `WhisperHotApp.swift` исключён из library через Package.swift `exclude`. При добавлении нового `@main` entry point нужно обновить exclude.

**Альтернативы.** Выделить только тестируемые модули в отдельный target — рассматривался, но полный split чище.

---

## ADR-009 — L10n.swift: enum-based локализация, не Apple .lproj

**Контекст.** Нужен русский/английский UI. SwiftPM executable target без Xcode project не поддерживает .lproj bundles стандартно.

**Решение.** `L10n.swift` — enum со static computed properties. Читает `Preferences.appLanguage` и возвращает нужную строку. ~150 строк, покрывает весь SettingsView + меню.

**Обоснование.**
- Работает без Xcode project, без .lproj, без genstrings.
- Compile-time safe — опечатка = ошибка компиляции.
- Достаточно для 2 языков.

**Последствия.**
- Не реактивный: SwiftUI перерисовывает при смене @AppStorage, но другие окна (menu items) обновляются только при `menuWillOpen`.
- При 10+ языков стоит перейти на `String(localized:)` или `swift-gen`.

**Альтернативы.** `NSLocalizedString` + .lproj — стандартный подход, но требует Xcode project для генерации. `swift-gen` — overkill для 2 языков.

---

## ADR-010 — Whisper install через Homebrew, не прямая загрузка бинаря

**Контекст.** Нужна one-click установка whisper.cpp. Варианты: скачать бинарь с GitHub Releases или запустить `brew install`.

**Решение.** Homebrew-backed install. `WhisperInstaller` запускает `brew install whisper-cpp` + скачивает ggml-base.bin с HuggingFace.

**Обоснование (по рекомендации Codex).**
- GitHub Releases whisper.cpp не имеет стабильных pre-built ARM64 macOS CLI asset'ов.
- Homebrew разрешает зависимости (ggml, sdl2).
- Homebrew bottle — signed и верифицированный.

**Последствия.** Homebrew обязателен. Если его нет — показываем инструкцию установки. App Sandbox несовместим с `Process` → `brew` (не используем sandbox).

**Альтернативы.** Прямая загрузка бинаря с GitHub — отвергнута из-за нестабильных asset'ов и supply-chain risk.

---

## ADR-011 — HTTPS-only для custom endpoint

**Контекст.** Пользователь вводит custom endpoint URL для пост-обработки. Транскрипты и API-ключи отправляются на этот URL.

**Решение.** Только `https://` разрешён. `http://` запрещён даже для localhost. Аудит Codex выявил credential leak при http fallback на `example.com`.

**Обоснование.** Транскрипты содержат всё, что пользователь сказал. Отправка по http — утечка приватных данных. Polza.ai и все серьёзные провайдеры поддерживают https.

**Последствия.** Нельзя использовать локальный LLM-сервер на http://localhost. Для этого есть Local LLM (llama-cli subprocess) — не нужен HTTP вообще.

**Альтернативы.** Разрешить http для localhost — рассматривалось, отвергнуто ради простоты правила.

---

## ADR-012 — Технический словарь: prompt hints + word replacements

**Контекст.** STT часто неправильно распознаёт технические термины: "commit" → "коммит", "deploy" → "деплой".

**Решение.** Два слоя:
1. Vocabulary hints — передаются STT провайдеру как `prompt` parameter (bias).
2. Word replacements — применяются после транскрипции, до LLM-обработки. 16 встроенных правил, редактируемые в Settings.

**Обоснование.**
- Prompt hints — стандартная фича Whisper API, zero-cost.
- Word replacements — простой substring replace, case-insensitive. Работает мгновенно.
- Замены до LLM: LLM получает уже правильные термины.

**Последствия.**
- Substring matching может ломать длинные слова ("пушкин" → "pushкин"). Codex отметил, но для tech terms это редкий edge case.
- е/ё не эквивалентны в Swift — добавлены оба варианта в defaults (мерж + мёрж).

**Альтернативы.** Whole-word matching — правильнее, но сложнее для пользовательских правил. Отложено.

---

## Про будущее (pending / не принято)

- **Streaming транскрипция.** Plan в `docs/streaming-plan.md`. Deepgram/AssemblyAI ~$8/мес. Отложено — batch с Groq (0.5 сек, $0.90/мес) достаточен.
- **App Sandbox.** Несовместим с `Process` для brew/whisper/llama. Не активирован.
- **Apple Developer ID + нотаризация.** Убрал бы проблему с Gatekeeper ($99/год). Не приоритет для personal build.
- **Autoupdate (Sparkle).** Проверка обновлений есть, автоустановка — нет.
- **Дальнейший split MenuBarController.** 828 строк — всё ещё много. Можно выделить MenuBuilder, RecordingStateMachine.

---

## Как обновлять этот файл

1. Любое **решение**, которое меняет стек, слой, границу или инфраструктуру, — новый ADR-N.
2. Не переписывай старые ADR. Если решение отменяется — добавь новый ADR со ссылкой `Supersedes ADR-N`.
3. Не описывай реализации (для этого `ARCHITECTURE.md`). Описывай **почему**.
4. Формат — **Контекст → Решение → Обоснование → Последствия → Альтернативы**.
5. Если целевая архитектура расходится с реализацией — укажи drift явно.
