# Продолжение STATUS — WhisperHot tech debt session

Дата: 2026-05-08
Версия после сессии: **0.6.8** (bump'нули в конце через /document-release
для shipping реального bug fix F015 — tilde-expansion в LocalLLMProcessor;
CHANGELOG [0.6.8] описывает всю волну рефактора + bug fix)
Ветка: `main` (16+ коммитов pushed на origin)

---

## Что сделано в этой сессии

### 1. Tech debt audit
Запустили `/tech-debt-audit` — получили `TECH_DEBT_AUDIT.md` с **36 находками** по 9 измерениям, ранжированными по Critical/High/Medium/Low + Effort. Файл закоммичен в репозиторий.

### 2. Реализовано 13 пунктов из аудита (Quick Wins + 2 Top-5 + F001 partial)

Все коммиты прошли Codex review (метод: посылал каждый diff в codex exec adversarial review, P1/P2 фиксил в том же коммите).

| Commit | ID | Что | Side effect |
|--------|----|------|-------------|
| `9c38ec8` | F002+F034 | Удалён dead `Sources/WhisperHot/WhisperHotApp.swift` (был исключён из компиляции через Package.swift) + stale comment | -19 строк |
| `5521420` | F003 | `DataBuffer` (был triplicated byte-for-byte) → `Sources/WhisperHot/Concurrency/DataBuffer.swift` | -33 строк |
| `16599fa` | F004 | `isLocalWhisperReady` (дубликат в MenuBarController + TranscriptionCoordinator) → `Preferences.isLocalWhisperReady` | single source |
| `4248f79` | F008 | Удалён dead `hadErrorLock` в AudioRecorder | -5 строк |
| `db675df` | F010 | `IndicatorStyle.displayName` / `AudioRetention.displayName` (English-only) → `L10n.indicatorStyleName(_:)` / `L10n.audioRetentionName(_:)` | Codex caught: смесь рус/англ в `untilQuit` локализации, исправлено |
| `cffd722` | F012 | localLLM TextField bindings: raw UserDefaults → @AppStorage | consistency |
| `3651f89` | F013 | Заполнены 4 missing Defaults entries (appLanguage, vocabularyHints, localLLMBinary/Model) + регистрация в `registerDefaults()` | single source of truth |
| `8016474` | F015 | `PostProcessingError.missingAPIKey` reuse hack → правильные `.missingLocalBinary(path:)` / `.missingLocalModel(path:)` | **Codex поймал 2 РЕАЛЬНЫХ бага**: (a) tilde-expansion mismatch (`~/models/foo.gguf` ошибочно отбраковывался — Settings даже это как пример показывает!), (b) silent skip когда пути пустые |
| `f3391c6` | F022 | Tests: WordReplacementTests.swift (12 cases) + миграция дублирующих тестов из ContextRouterTests | Codex caught: substring corruption (`пуш` ломает `пушка`) — pin'нул тестом |
| `09bf08f` | F011 | 7 hardcoded URLs в 3 файлах → `Sources/WhisperHot/Networking/Endpoints.swift` (nested namespace OpenAI/OpenRouter/Groq/PolzaAI с stt+chat URL константами) | single source |
| `be3dc79` | F009 | **36 inline `L10n.lang == .ru ? ".." : ".."`** → 32 ключа в L10n.swift (string + interpolated functions) | grep clean: ноль остатков вне L10n.swift |
| `aa1905a` | F001a | KeychainTests.swift (11 cases) + Keychain refactor: добавлен `service:` параметр на все public methods (default = `Keychain.defaultService`). saveRaw/readRaw helpers экстрагированы — incidentally закрыли F030 (~50 строк дедупа). Тесты используют UUID-prefixed service, не трогая user's real keychain. |
| `98b52da` | F001b | HistoryStoreTests.swift (10 cases) + HistoryStore refactor: новый init с инжектируемыми `storageDirectoryOverride`, `keychainService`, `retentionDaysProvider`, `maxEntriesProvider`. Production callers (`HistoryStore()`) unchanged. |
| `a995c68` | docs | TECH_DEBT_AUDIT.md commit (был untracked) |

### 3. Метрики

- **Тесты: 21 → 54** (+157%). Покрытие: Keychain, HistoryStore (encryption + orphan detection + key length validation), WordReplacement, ContextRouter, FallbackTranscriptionService.
- **Архитектура**: 2 новых модульных файла (Concurrency/, Networking/), de-dup ~80 строк.
- **L10n discipline**: 0 inline ternaries вне L10n.swift (было 36+).
- **Build**: zero compile warnings, 33→54 tests green в release.

### 4. Codex поймал 7 P2 багов
Перечисляю реальные находки (не просто стилевые):
- F010: смесь "best-effort; пропускается на force-quit / краше" (RU + EN mix)
- F015 #1: silent skip empty-paths кейса
- F015 #2: tilde-expansion mismatch (валидный `~/foo` отбраковывался)
- F022 #1: weak overlap test заменён на substring-pin
- F022 #2: missing Cyrillic case-insensitive test (defaults — русские термины!)
- F022 #3: contains() → exact-equality для defaults assertion
- F022 #4: дубликаты в ContextRouterTests мигрированы

---

## Что остаётся на будущее

### Из Top 5 не сделано

#### F005 — Split SettingsView.swift (1026 LOC)
**Зачем**: hottest churn file (14 commits в 6 mo), 30+ @AppStorage props в одном файле.
**Как**:
- Создать `Sources/WhisperHot/Settings/Tabs/` (или просто доп. файлы в Settings/)
- Извлечь 6 tab свойств в свои файлы:
  - `SettingsRecordingTab.swift` (recordingTab)
  - `SettingsProvidersTab.swift` (providersTab + apiKeyControls + apiKeyAndModelSection + localWhisperSection)
  - `SettingsPostProcessingTab.swift` (postProcessingTab + ppModelSection)
  - `SettingsHotkeyTab.swift` (hotkeyTab)
  - `SettingsHistoryPrivacyTab.swift` (historyPrivacyTab)
  - `SettingsUpdatesTab.swift` (updatesTab)
- Каждый tab — отдельный `View` struct с собственными `@AppStorage`, либо общий `SettingsState: ObservableObject` если нужно делиться состоянием между табами
- Aim: каждый файл <400 LOC
**Риск**: SwiftUI-регрессия. У нас НЕТ UI-тестов на SettingsView. Делать ОЧЕНЬ внимательно, проверять каждый таб руками после рефакторинга. Сразу после split'а — manual smoke pass: открыть Settings, потыкать каждую секцию.
**Effort**: ~1ч + 30мин QA

#### F006 — Split MenuBarController.swift (871 LOC)
**Зачем**: 2-й по churn'у файл (13 commits в 6 mo). Госд-objект: state machine + UI construction + hotkey lifecycle + transcription orchestration + paste + windows.
**Как**:
- `MenuBuilder.swift` — `buildMenu()` + `refreshDynamicMenuState()`. Менюшная конструкция и retitle-логика.
- `RecordingStateMachine.swift` — `toggleRecording`, `startRecordingFromMenu`, `stopRecordingFromMenu`, `kickOffTranscription`, `finishTranscription`, `handleAutoStop`. Pure state-machine, без UI.
- `HotkeyTransport.swift` — Carbon vs Fn switch, `syncHotkeyBindings`, retry timer, arm/disarm. Сейчас всё это inline в init + 6 private методах.
- MenuBarController остаётся как coordinator, ~300 LOC.
**Риск**: ВЫСОКИЙ. State machine критичен (recording lifecycle), любой race регресс ломает основной user flow. **Сначала** покрыть state machine тестами (mock'ать AudioRecorder и TranscriptionCoordinator), **потом** split'ить. Иначе не поймать регресс.
**Effort**: 2-3ч с тестами

#### F001 — Полный backfill тестов
Сделано в этой сессии: WordReplacement (12), Keychain (11), HistoryStore (10) = 33.
Осталось:
- **Providers** (OpenAICompatibleSTTProvider, OpenRouterAudioProvider) — мокать URLSession через URLProtocol stub. Минимум: missing-key path, oversized-file path, 4xx body capture, empty-transcript handling, multipart body shape pin.
- **PasteService guards** — refactor `deliver` чтобы environment (frontmost, AX trust, secure input, pasteboard) был injected closures. Потом тестировать decision tree.
- **AudioRecorder lifecycle** — startRecording / stopRecording orderings, tap teardown, error paths. Сложно из-за AVAudioEngine, может потребовать мок-tap.
- **TranscriptionCoordinator.run** — pipeline test с mock Service + mock LLMPostProcessor.
- **Preferences round-trip** — закодировать/декодировать каждый custom struct через UserDefaults (contextRules, wordReplacements).
**Effort**: 3-4ч на всё

### Низкоприоритетное / не делал

- **F009 enforcement**: lint-правило в swift-check или Codex-check на PR — fail если `L10n.lang == .ru` появляется вне L10n.swift. Сейчас "ноль" обеспечивается только моим грепом. Без enforcement'а regress неизбежен.
- **F005 Settings extraction следствие**: `KeychainBindingViewModel` для пары key+status (повторяется 5 раз в SettingsView).
- **F029 — os.Logger**: 61 NSLog → структурированные `Log.transcription` / `Log.audio` / `Log.history`. Низкоприоритетно для personal app, но Console.app filtering получили бы бесплатно.
- **F032 — HTTP error body sanitization**: сейчас 300-char truncation, no scrubbing of non-printable. Будущий провайдер может echo'ить request body в error → транскрипт утечёт в баннер.

### Streaming transcription — отдельное P3 XL deferred
План в `docs/streaming-plan.md`. Deepgram/AssemblyAI ~$8/мес. Не приоритет — Groq batch ($0.90/мес, 0.5s latency) покрывает основной use case.

### Возможный 0.6.8 release
**F015 фикс tilde-expansion — это РЕАЛЬНЫЙ пользовательский баг.** Если у пользователя в Local LLM путь `~/models/foo.gguf` (а Settings показывает именно так как пример!), пост-процессинг падал с misleading "API key is not set" error. Достойно patch-релиза:
- `VERSION` 0.6.7 → 0.6.8
- `Resources/Info.plist` CFBundleShortVersionString + CFBundleVersion bump
- CHANGELOG entry под `[0.6.8]` describing the fix + the L10n sweep + the test backfill
- `./build.sh` && `./build-dmg.sh`
- `gh release create v0.6.8 --latest <dmg>` (per memory: автопубликация после version bump)

Не делал в этой сессии потому что user сказал "коммит и push", не "релиз". Но это разумный следующий шаг.

---

## Контекст для следующей Claude-сессии

### Что НЕЛЬЗЯ забыть
1. **Codex review every stage** (memory: feedback_codex_every_stage.md). Перед commit'ом — `/codex` на diff.
2. **Tilde expansion в paths** — мы это исправили в LocalLLMProcessor, но в LocalWhisperProvider (`Sources/WhisperHot/Transcription/Providers/LocalWhisperProvider.swift`) такая же логика. Возможно тоже стоит проверить — может там та же история.
3. **HistoryStore теперь имеет инжектируемый init** — production вызовы `HistoryStore()` работают, но если будешь трогать конструктор, помни что тесты от него зависят.
4. **Keychain теперь имеет `service:` параметр** на всех 5 методах — production использует default `Keychain.defaultService`, тесты UUID-prefixed.

### Файлы, которые я создал
- `Sources/WhisperHot/Concurrency/DataBuffer.swift` (extracted)
- `Sources/WhisperHot/Networking/Endpoints.swift` (URL namespace)
- `Tests/WhisperHotTests/WordReplacementTests.swift` (12 cases)
- `Tests/WhisperHotTests/KeychainTests.swift` (11 cases)
- `Tests/WhisperHotTests/HistoryStoreTests.swift` (10 cases)
- `TECH_DEBT_AUDIT.md` (36 findings — справочник для будущих рефакторов)

### Файлы, которые я тронул (не создал)
- `Package.swift` (убрал exclude)
- `Sources/WhisperHot/MenuBarController.swift` (delegation + L10n sweep)
- `Sources/WhisperHot/Settings/Preferences.swift` (Defaults + sttEndpoint + Endpoints integration)
- `Sources/WhisperHot/Settings/SettingsView.swift` (L10n sweep + @AppStorage cleanup + L10n display names)
- `Sources/WhisperHot/Localization/L10n.swift` (+32 keys)
- `Sources/WhisperHot/Audio/AudioRecorder.swift` (-hadErrorLock)
- `Sources/WhisperHot/Keychain/Keychain.swift` (refactor для testability)
- `Sources/WhisperHot/History/HistoryStore.swift` (refactor для testability)
- `Sources/WhisperHot/PostProcessing/PostProcessingPreset.swift` (новые error cases)
- `Sources/WhisperHot/PostProcessing/LocalLLMProcessor.swift` (использует новые errors + tilde expansion fix)
- `Sources/WhisperHot/Transcription/TranscriptionCoordinator.swift` (Endpoints + always-construct LocalLLMProcessor)
- `Sources/WhisperHot/Transcription/Providers/OpenRouterAudioProvider.swift` (Endpoints)
- `Sources/WhisperHot/Transcription/Providers/LocalWhisperProvider.swift` (-DataBuffer)
- `Sources/WhisperHot/LocalSetup/WhisperInstaller.swift` (-DataBuffer + L10n sweep)
- `Sources/WhisperHot/LocalSetup/UpdateChecker.swift` (L10n sweep)
- `Sources/WhisperHot/Indicator/StudioPanelView.swift` (L10n sweep)
- `Tests/WhisperHotTests/ContextRouterTests.swift` (миграция WordReplacement тестов)

### Текущее состояние main
- 15 коммитов запушено в origin
- Working tree clean
- Tests 54/54 green в release
- VERSION = 0.6.8, Info.plist build = 15
- 0.6.8 GitHub release создан (gh release create v0.6.8)

### Стратегия для следующей сессии
**Самые приоритетные оставшиеся вещи** (после shipping 0.6.8):
1. **F005 — split SettingsView** (1007 LOC, 6 tab-файлов). Hottest churn. Без UI-тестов осторожно + manual QA после.
2. **F006 — split MenuBarController** (~840 LOC). Сначала покрыть state machine тестами (mock AudioRecorder + TranscriptionCoordinator), ПОТОМ split. Иначе риск регресса в основном recording flow.
3. **F001 продолжение** — Providers (URLProtocol mock), PasteService guards, TranscriptionCoordinator pipeline test, AudioRecorder lifecycle.

**Опциональное низкоприоритетное**:
- F009 enforcement: lint-rule на `L10n.lang == .ru` outside L10n.swift.
- F029: 61 NSLog → структурированный os.Logger.
- Streaming transcription (P3 deferred, plan в `docs/streaming-plan.md`).
