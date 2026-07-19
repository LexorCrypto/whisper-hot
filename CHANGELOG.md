# Changelog

Все значимые изменения в WhisperHot (до 0.3.0 — WhisperLocal).

## [0.8.0] — 2026-07-19

Обновление визуальной идентичности: новый логотип-иконка и переработанные
индикаторы записи в едином стиле с сайтом.

### Для пользователей

- **Новая иконка приложения** — фирменный волновой логотип (пять
  градиентных баров accent→violet на тёмном squircle), тот же, что на сайте.
- **Индикаторы записи переработаны и сокращены до трёх стилей:**
  «Минимальный» (компактная капсула с пятью барами-эхо логотипа),
  «Средний» (волна из 24 баров + таймер) и «Большой» (плотная симметричная
  волна + таймер и подсказка хоткея). Все с градиентом accent→violet и
  тёмным «стеклом» в стиле сайта. Прежний «Только менюбар» и старые стили
  (pill / классика / капсула / студия) удалены; дефолт — «Минимальный».
- Индикатор теперь всегда показывается при записи; неизвестные сохранённые
  значения стиля (старые pill/waveform/menubar/…) отображаются как «Минимальный».

### Для разработчиков

- `IndicatorStyle` сокращён до `minimal` / `medium` / `large` (дефолт
  `minimal`, неизвестный сохранённый rawValue → `.minimal`). Удалены
  `MiniPillView` / `ClassicWaveformView` / `FloatingCapsuleView` /
  `StudioPanelView`; добавлены `MinimalIndicatorView` / `MediumIndicatorView`
  / `LargeIndicatorView`.
- `IndicatorController` больше не имеет menubar-ветки (панель всегда
  рендерится при записи) и маппит три стиля на три view.
- `Resources/WhisperHot.icns` перегенерирован из логотипа (1024 → полный iconset).
- Лендинг: версия подтягивается автоматически — `BUILD_VERSION` из корневого
  `VERSION` (prebuild-скрипт) как fallback + рантайм-fetch последнего
  GitHub Release; отражается в шапке и футере через Zustand-стор.
- Версия поднята до 0.8.0 (CFBundleVersion 20).
- Распространяется как Developer ID-подписанный DMG; **не нотаризован**
  (нотаризация требует app-specific password), поэтому Gatekeeper покажет
  предупреждение при первом запуске — снять карантин `xattr -cr`.

### Проверка

- `swift build` — OK. Рендер трёх индикаторов (recording/transcribing) через
  ImageRenderer — размеры 112×34 / 248×46 / 340×96, градиентная волна OK.
- `swift test` — 54 теста OK.

## [0.7.2] — 2026-05-25

Emergency hotfix. `0.7.1` пытался ремонтировать Keychain ACL через
`kSecAttrAccess`, но на живых user items это могло зациклить macOS prompt:
после ввода login keychain password окно появлялось снова и снова.

### Для пользователей

- **Откатан risky Keychain ACL repair из 0.7.1.** WhisperHot больше не
  вызывает `SecAccessCreate` / `SecItemUpdate(kSecAttrAccess)` для
  существующих API keys.
- **Главное окно больше не читает API key при запуске.** Setup показывает,
  что cloud provider не проверяется на старте, чтобы приложение могло
  открыться без Keychain prompt-loop.
- **Keychain читается только при явном действии.** Например, когда пользователь
  открывает Providers/Settings или запускает транскрипцию, где API key
  реально нужен.

### Для разработчиков

- Убран `Darwin` import, dynamic lookup `SecAccessCreate`, `kSecAttrAccess`
  на add/update и best-effort ACL repair path.
- `MainWindowModel.readProviderSetupStatus` теперь работает в no-Keychain
  mode для cloud-провайдеров на launch/UI refresh.
- Добавлены L10n строки для deferred provider key check.
- Подготовлен Developer ID distribution path: `SIGNING_MODE=developer-id`
  подписывает `.app` с Hardened Runtime/audio-input entitlement, DMG
  подписывается Developer ID Application certificate, отправляется в
  Apple notarization и staple-ится через `xcrun stapler`.

### Проверка

- `swift build -c release` — OK.
- `swift test` — OK.
- `git diff --check` — OK.

## [0.7.1] — 2026-05-25

Patch-релиз после main-window MVP. Исправляет повторяющиеся запросы
macOS Keychain access после установки свежей сборки поверх предыдущей.

> Superseded by `0.7.2`: ACL repair path мог вызвать повторяющийся
> Keychain prompt-loop на живых user items.

### Для пользователей

- **Keychain больше не должен просить пароль после каждой сборки.**
  WhisperHot теперь ремонтирует ACL существующих production Keychain
  items после успешного доступа и создаёт новые items с явным access
  control для текущей signed identity.
- **Setup перестал дёргать Keychain каждые 0.75 секунды.** Главное окно
  по-прежнему обновляет состояние записи и permissions по таймеру, но
  readiness текущего STT-провайдера перечитывает API key только при
  открытии окна, изменении настроек или save/delete ключа.

Ожидаемое поведение: при первом запуске `0.7.1` macOS может один раз
попросить доступ к старым ключам. После `Разрешить всегда` приложение
repair-ит ACL, и следующие сборки с тем же `whisper-hot-local`
сертификатом не должны спрашивать заново.

### Для разработчиков

- `Keychain.saveRaw` добавляет `kSecAttrAccess` для production service
  `com.aleksejsupilin.WhisperHot`; тестовые service-id остаются без
  ACL-override, чтобы XCTest не провоцировал системные prompts.
- `Keychain.readRaw` делает best-effort ACL repair для старых production
  items после успешного `SecItemCopyMatching`.
- Добавлена notification `WhisperHot.keychainDidChange`, чтобы Main Window
  мог обновлять readiness без polling secrets.
- `MainWindowModel.refresh` получил флаг `includeProviderSetup`; timer
  refresh больше не читает Keychain.

### Проверка

- `swift build -c release` — OK, без warnings.
- `swift test` — 54/54 passed.
- `git diff --check` — OK.

## [0.7.0] — 2026-05-25

Product/UX релиз. WhisperHot больше не ощущается как набор пунктов в
menu bar: появился полноценный macOS shell с главным окном, Dock-иконкой,
Dashboard, встроенными настройками, историей и Setup.

### Для пользователей

- **Полноценное главное окно.** Приложение теперь запускается как обычное
  macOS-приложение с Dock-иконкой и окном `WhisperHot`. В sidebar доступны
  Dashboard, Recording, Providers, Post-processing, Hotkey, Privacy,
  Updates, History и Setup.
- **Menu bar остался быстрым контроллером.** Status item не удалён:
  оттуда по-прежнему можно стартовать/остановить запись, сменить provider,
  открыть историю/настройки/permissions и вернуть главное окно через
  `Open WhisperHot`.
- **Dashboard стал рабочей точкой входа.** Он показывает текущий STT route,
  модель, hotkey, post-processing/context/history/autopaste/local fallback
  и даёт primary-кнопку записи.
- **Запись из Dashboard не вставляет текст обратно в WhisperHot.** Перед
  стартом записи главное окно прячется, WhisperHot возвращает фокус в
  предыдущее приложение и только затем начинает запись. Это сохраняет
  привычный auto-paste flow.
- **Настройки встроены в главный shell.** Recording / Providers /
  Post-processing / Hotkey / Privacy / Updates теперь открываются как
  разделы общего окна, без вложенного sidebar. Старое отдельное окно
  Settings оставлено как fallback из menu bar.
- **History встроена в главное окно.** Отдельное History окно сохранено,
  но основной путь теперь внутри главного shell.
- **Setup стал readiness-чеклистом.** Он показывает Microphone,
  Accessibility, Input Monitoring и готовность текущего STT-провайдера:
  cloud API key в Keychain или local whisper.cpp binary+model. Когда всё
  готово, строки показывают компактный зелёный бейдж `Готово`.
- **Windows support зафиксирован как продуктовая цель.** Реализация
  остаётся macOS-only, но roadmap вынесен в
  `docs/windows-support-plan.md`, чтобы не смешивать текущую macOS-доводку
  с будущим Windows-портом.

### Для разработчиков

- `LSUIElement` удалён из `Resources/Info.plist`; entrypoint ставит
  `NSApplication.ActivationPolicy.regular`.
- `AppDelegate` теперь создаёт `MenuBarController` +
  `MainWindowController`, показывает главное окно на launch и
  восстанавливает его на Dock/reopen.
- `MenuBarController` получил interface bridge:
  `InterfaceSnapshot`, `toggleRecordingFromInterface`, open handlers для
  Main Window / Settings / History / Onboarding и доступ к HistoryStore /
  PermissionsCoordinator для SwiftUI shell.
- Добавлен `Sources/WhisperHot/MainWindow/MainWindowController.swift`:
  `NavigationSplitView` shell, Dashboard, Setup, embedded Settings sections
  и polling model для state/permissions snapshots.
- `SettingsView` получил `embeddedSection` mode. В отдельном Settings
  окне он по-прежнему показывает собственный sidebar, а в главном окне
  рендерит только выбранную секцию.
- `HistoryView` вынесен в переиспользуемый `TranscriptHistoryView`, чтобы
  встроенная History и отдельное окно использовали один UI.
- Settings / History / Onboarding / Main Window очищают stale
  `previousApp`, если открыты из самого WhisperHot.
- Документация обновлена: README, ARCHITECTURE, decisions, status и
  Windows roadmap.

### Проверка

- `swift build -c release` — OK.
- `swift test` — 54/54 passed.
- `./build.sh` — OK.
- Window-only visual QA главного окна и Setup — OK.
- Click-through QA без записи микрофона — OK.
- Sensitive recording QA с согласием пользователя — OK:
  Dashboard start → тестовый audio input → status-menu stop → Groq
  transcript → auto-paste в новый TextEdit-документ.

## [0.6.9] — 2026-05-09

Stability релиз. Закрывает класс багов «приложение виснет после возврата
Mac'а из sleep mode, помогает только перезапуск». Пять атомарных коммитов,
каждый прошёл Codex review.

### Для пользователей

- **Менюбар-приложение больше не зависает после возврата из sleep.** Если
  раньше после того как Mac уходил в сон во время работы или сразу после
  записи, иконка переставала реагировать и приходилось перезапускать
  WhisperHot — теперь это починено. На `willSleep` приложение отменяет
  активную транскрипцию и сбрасывает audio engine; на `didWake`
  перерегистрирует Carbon hotkey и делает defensive cleanup на случай
  dark-wake / hibernate сценариев когда `willSleep` вообще не сработал.
- **Cloud STT и LLM-cleanup больше не залипают навечно при потере сети
  во время сна.** Раньше URLSession.shared имел `timeoutIntervalForResource
  = 7 days` — request, у которого ядро снесло TCP-сокет во время сна,
  мог жить неделю без ошибки, держа стейт `.transcribing` и блокируя
  hotkey. Все cloud-провайдеры (OpenAI / OpenRouter / Groq / PolzaAI / LLM
  cleanup) переведены на ephemeral URLSession с
  `timeoutIntervalForResource = 180s` и `waitsForConnectivity = false`.
- **Если запись или транскрипция прервались сном, WAV не удаляется.**
  Файл остаётся на диске, его подберёт retention sweep по твоей политике
  (`.untilQuit` / `.oneHour` / `.forever` теперь не теряют единственную
  копию аудио из-за случайного сна).

### Для разработчиков

Корневой sympom — никакой sleep/wake handling в коде вообще не было
(grep'ом подтверждено: ноль observer'ов на NSWorkspace.willSleep /
didWake до этого релиза). Кросс-консультация с Codex выявила три
архитектурных дефекта, которые стреляли каскадом:

1. `Task.detached` для транскрипции запускался **без сохранения handle**.
   Никто не мог отменить stranded request. И stale Task мог дойти до
   `finishTranscription` уже после того как пользователь начал новую
   запись, обнулив state посреди работы.
2. `URLSession.shared` с дефолтным 7-дневным `timeoutIntervalForResource`.
3. `AudioRecorder.stopRecording()` ждал `tapGroup.wait()` и
   `writerQueue.sync {}` на main thread — если callback или write
   wedged во время suspend, main thread зависал намертво.

Решение разбито на 5 атомарных коммитов:

**Step 1 — instrumentation (`ef5ad33`)**
- `didSet` observer на `RecorderState` логирует все переходы.
- `Task.detached` body обёрнут в launching/returned NSLog с epoch и
  outcome tag.
- `NSWorkspace.willSleep` / `didWake` observers — пока только NSLog,
  separate `workspaceTokens` array (NSWorkspace.shared.notificationCenter
  ≠ NotificationCenter.default; removeObserver на «не своём» центре
  silently no-op).
- Phase markers в `TranscriptionCoordinator.run`:
  `stt-begin / stt-end / stt-failed / pp-begin / pp-end (ok|failed)`.
- Codex поймал format-string injection: `error.localizedDescription`
  и `ppOptions.model` теперь идут через `"%@"`, а не interpolated
  format string (provider error body может содержать `%`-последовательности
  которые NSLog трактует как specifiers).

**Step 2 — task ownership + epoch guard (`459aeaa`)**
- `private var transcriptionTask: Task<Void, Never>?` — handle хранится,
  доступен для `cancel()`.
- `private var transcriptionEpoch: UInt64` — инкремент на каждый
  `kickOffTranscription`. Запускающийся Task захватывает свой epoch,
  при возврате `deliverTranscriptionResult(outcome:epoch:)` сравнивает
  с текущим. Mismatch ⇒ результат от cancelled / superseded run, дропаем
  до того как он зайдёт в `finishTranscription`.

**Step 3 — sleep/wake actions (`19744b5`)**
- `handleWorkspaceWillSleep`: для `.transcribing` отменяет task, бампает
  epoch, обнуляет UI bookkeeping. WAV оставляется на диске
  (matches `.failure` path — retention sweep управляет).
- `handleWorkspaceDidWake`: `syncHotkeyBindings()` против stale
  Carbon `EventHotKeyRef`, с guard на `isHotkeyRecorderArmed` чтобы не
  ломать UI Settings → Hotkey recorder если sleep случился прямо во
  время capture.
- Codex поймал две P2: retention bypass (теперь не удаляем WAV) +
  hotkey-armed guard.

**Step 4 — ephemeral URLSession (`1f9d287`)**
- Новый файл `Sources/WhisperHot/Networking/HTTPClient.swift`. Один
  shared URLSession для всех cloud-провайдеров:
  `URLSessionConfiguration.ephemeral`, `waitsForConnectivity = false`,
  `timeoutIntervalForRequest = 60`, `timeoutIntervalForResource = 180`.
- Per-request `URLRequest.timeoutInterval` overrides сохранены
  (60s OpenAI / 120s OpenRouter / 60s LLM). Session-level
  `timeoutIntervalForResource` — safety cap на случай если
  per-request override не сработал.
- DI preserved: тесты могут инжектить `urlSession:` параметром
  (URLProtocol stubs).
- `LocalWhisperProvider` / `LocalLLMProcessor` не затронуты — они
  через `Process`, не URLSession.

**Step 5 — AudioRecorder.resetAfterWake + per-session primitives (`67a3485`)**
- `ActiveSession` теперь владеет своими `tapGroup: DispatchGroup` и
  `writerQueue: DispatchQueue` (label `*.writer.<id>`). Раньше они
  были shared на инстанс — и заклинивший callback из abandoned session
  отравлял `tapGroup.wait()` следующего `stopRecording()` навсегда.
- `ActiveSession.id: UInt64` — монотонный ID. Tap closure захватывает
  session **strongly**: stale callback из старой сессии не дотянется
  до WAV новой записи.
- `processTapBuffer(buffer:session:)` гейтит ВСЁ (RMS update + write
  enqueue) на `isLive = sessionLock.withLock { $0?.id == session.id }`.
  Late callback после `stopRecording` / `resetAfterWake` бейлит до
  записи в файл, который caller уже отдал транскрибатору.
- `AudioRecorder.resetAfterWake()`: best-effort non-blocking teardown.
  Removes tap, stops engine, clears slot, resets isRecording. **Никогда
  не ждёт** `tapGroup` / `writerQueue` (это и есть suspect freeze
  site). Idempotent. Orphan WAV остаётся retention sweep'у.
- `MenuBarController.handleWorkspaceWillSleep`/`handleWorkspaceDidWake`
  теперь обрабатывают `.recording` (через `resetAfterWake`) и
  dark-wake / hibernate path (когда `willSleep` не сработал).
  Helper `resetControllerStateToIdle()` shared между ветками.
- `stopRecording` reorder: capture session + clear slot **до**
  `wait()` — late callback наблюдает cleared slot и бейлит.
- Codex поймал 4 P1/P2 в три прохода: stale tap → successor WAV;
  controller state desync after dark-wake; shared `tapGroup`/`writerQueue`
  poisoned by wedged callback; late tap writes after stop.

### Известные ограничения (намеренно вне scope)

- `LocalWhisperProvider` / `LocalLLMProcessor` запускают `Process`
  внутри `withCheckedThrowingContinuation` без cancellation handler.
  `Task.cancel()` пометит Swift Task cancelled, но subprocess
  продолжит работать. Заметно только если пользователь — на Local
  Whisper / Local LLM (cloud-only пользователей это не касается).
  Tracked для отдельного фикса.
- Нет UI / state-machine тестов на `MenuBarController`. Project
  status.md F006 фиксирует этот пробел; до его закрытия рефакторы
  state machine идут под manual smoke pass.

## [0.6.8] — 2026-05-08

Tech debt + bug fix релиз. Реальный пользовательский баг в Local LLM
post-processing исправлен; плюс волна рефакторинга, поднявшая
покрытие тестами с 21 до 54 кейсов.

### Для пользователей

- **Local LLM post-processing теперь принимает `~/...` пути.** Если у
  тебя в Settings → Post-processing → Local LLM путь к llama-cli или
  GGUF-модели начинается с `~` (как Settings даже показывает в плейсхолдере:
  `~/models/llama-3.1-8b-q4.gguf`), пост-обработка раньше падала с
  misleading «API key is not set». Теперь tilde раскрывается до
  `/Users/<you>/...` ДО проверки существования файла, и работает.
- **Понятные сообщения об ошибках Local LLM.** Когда llama-cli не
  настроен или GGUF-модель не найдена, теперь видишь конкретное
  «Local LLM binary path is not set» / «Local LLM model file not found
  at <path>» вместо общего «API key is not set».
- **Тоггл «Auto-switch to Offline when slow» отключается, если local
  whisper.cpp не настроен.** Раньше можно было поставить галочку без
  фолбэка и race-логика тихо ничего не делала. (Это уже было в 0.6.7,
  здесь без изменений.)

### Для разработчиков

Эта волна — целенаправленный refactor pass по `TECH_DEBT_AUDIT.md`:
36 находок по 9 измерениям, 13 пунктов закрыты с Codex-review каждого
коммита. Codex поймал 7 P2-проблем по ходу, включая два РЕАЛЬНЫХ бага
(tilde expansion + silent skip empty-paths в Local LLM).

Структурные изменения:
- `Sources/WhisperHot/Concurrency/DataBuffer.swift` (новый) — общий
  thread-safe byte accumulator. Раньше был triplicated byte-for-byte
  в LocalWhisperProvider, WhisperInstaller, LocalLLMProcessor. (F003)
- `Sources/WhisperHot/Networking/Endpoints.swift` (новый) — single
  source of truth для HTTP-эндпоинтов всех провайдеров. 7 захардкоженных
  URL в 3 файлах сведены к одному namespace. (F011)
- `Preferences.isLocalWhisperReady` — выделен из дубликата в
  MenuBarController + TranscriptionCoordinator. (F004)
- `Sources/WhisperHot/WhisperHotApp.swift` удалён — был `@main`-decorated
  но excluded from compilation, реальный entry — `Sources/WhisperHotApp/main.swift`. (F002)

Локализация:
- 36 inline `L10n.lang == .ru ? "..." : "..."` тернариев свёрнуты в
  32 ключа в `L10n.swift`. Grep clean: ноль остатков вне самого файла. (F009)
- Двойные display-name'ы (English-only on enum + localized in L10n)
  свёрнуты — `IndicatorStyle.displayName` / `AudioRetention.displayName`
  удалены, `L10n.indicatorStyleName(_:)` / `L10n.audioRetentionName(_:)`
  становятся single source. (F010)

Errors:
- `PostProcessingError.missingAPIKey` больше не reuse'ится для
  «binary not found» / «model not found». Добавлены proper кейсы
  `.missingLocalBinary(path:)` / `.missingLocalModel(path:)` с
  диагностикой указывающей на правильный Settings-таб. (F015)

Cleanup:
- Удалён dead `hadErrorLock` в `AudioRecorder` (писали, не читали). (F008)
- localLLM TextField bindings: raw `UserDefaults.standard` → `@AppStorage`,
  consistency с остальным SettingsView. (F012)
- `Preferences.Defaults` filled out: `appLanguage`, `vocabularyHints`,
  `localLLMBinaryPath`, `localLLMModelPath` теперь там есть и
  регистрируются в `registerDefaults()`. (F013)

Testing (21 → 54 кейсов):
- `Tests/WhisperHotTests/WordReplacementTests.swift` (новый, 12 cases) —
  `applyAll` pipeline с пинна substring-corruption поведением (`пуш`
  ломает `пушка` в дефолтах — задокументировано тестом). (F022)
- `Tests/WhisperHotTests/KeychainTests.swift` (новый, 11 cases) — round-trip
  save/read/delete через UUID-prefixed test service. Keychain получил
  `service:` параметр на public methods + `saveRaw`/`readRaw` helpers
  (incidentally закрыли F030 — ~50 строк дедупа). (F001a)
- `Tests/WhisperHotTests/HistoryStoreTests.swift` (новый, 10 cases) —
  encrypt/decrypt round-trip, orphan detection, key length validation,
  prune-by-retention, prune-by-max-entries. HistoryStore получил
  инжектируемый init для test isolation. (F001b)

Документация:
- `TECH_DEBT_AUDIT.md` (новый) — 36 находок с file:line цитатами,
  ranked Critical/High/Medium/Low + Effort, top-5 outline + quick wins.
- `status.md` (новый) — handoff заметка для будущих сессий.
- `CLAUDE.md` — указатель на `status.md` при старте каждой сессии.

Codex review: PASS на каждом из 13 коммитов рефактора. 54/54 тестов
зелёные в release. Zero compile warnings.

## [0.6.7] — 2026-05-08

Багфикс-релиз. Закрывает 3 проблемы, найденные adversarial Codex-ревью на v0.6.6.

### Для пользователей

- **Тоггл «Auto-switch to Offline when slow» больше не молчит впустую.**
  Раньше можно было поставить галочку даже без настроенного локального
  whisper.cpp — и она ничего не делала, потому что race-логика тихо
  отключалась когда fallback недоступен. Теперь пункт меню становится
  серым и не кликабельным, если local whisper не настроен (нет путей к
  бинарю или модели), с подсказкой «Сначала настрой Local whisper.cpp в
  Settings → Providers».
- **Cancellation работает корректно при отмене записи.** Если по какой-то
  причине транскрипция отменяется (закрытие приложения, форс-стоп), она
  теперь действительно прерывается — а не догоняет локальной
  транскрипцией задним числом, как могло раньше.
- **Защита от corrupted-настроек.** Поле «timeout seconds» в настройках
  теперь обрезается до диапазона `[1, 3600]` секунд. Раньше любое значение
  больше ~18 миллиардов секунд переполняло `UInt64` при умножении на
  наносекунды и могло крашить старт транскрипции.

### Для разработчиков

- `FallbackTranscriptionService.transcribeWithTimeoutRace()`:
  - Timer-таска теперь использует `try await Task.sleep` (без `try?`),
    чтобы parent-task cancellation бросал `CancellationError` через
    `withThrowingTaskGroup`, а не маскировался как `.timeout` event с
    запуском local whisper после уже отменённого вызова.
  - Primary-таска проверяет `Task.isCancelled` после catch и re-raise'ит
    `CancellationError` вместо того чтобы конвертировать `URLError.cancelled`
    в `.primaryFailure`.
  - Clamp `autoOfflineTimeoutSeconds` к `max(1, min(seconds, 3600))` перед
    multiplication на `1_000_000_000` — defense от UInt64 overflow.
- `MenuBarController.refreshDynamicMenuState()` вычисляет
  `isLocalWhisperReady()` (зеркало `TranscriptionCoordinator.makeLocalFallbackIfReady`)
  и сетит `autoOfflineOnTimeoutMenuItem.isEnabled` соответственно. Tooltip
  локализован RU/EN.
- `TranscriptionCoordinator.fromPreferences()`: убран dead-code дубликат
  чтения `Preferences.vocabularyHints` (фактический поток hints
  происходит в `MenuBarController:662` через `TranscriptionOptions.prompt`).
- `Tests/WhisperHotTests/FallbackTranscriptionServiceTests.swift`:
  - `testParentCancellationPropagates` — `task.cancel()` после старта
    race должен прерывать, а не доводить fallback до конца.
  - `testToggleOnWithNilFallbackUsesLegacyPath` — race не должен
    запускаться когда fallback nil.
- `ContextRouterTests.testSlackMatchesCasual`: unused `let result =`
  заменён на `_ =` smoke check.
- Codex review: PASS, 25/25 тестов зелёные, no new warnings.

## [0.6.6] — 2026-05-08

### Для пользователей

- **Авто-переключение на Offline при медленной сети** (опционально).
  Новый тоггл в menu bar рядом с Provider submenu. Когда включён, при
  таймауте cloud-провайдера (10 секунд по умолчанию) WhisperHot
  отменяет cloud-запрос и догоняет локальной транскрипцией через
  whisper.cpp. Существующее поведение fallback'а на полностью offline
  ошибки (отсутствие сети, разрыв соединения) сохранено и работает
  независимо от тоггла. По умолчанию выключено — включается только
  если у тебя настроен local whisper.cpp И ты явно поставил галочку.
- **Новая иконка приложения.** Voice → Text waveform — слева
  вертикальная аудиоволна, справа три текстовых строки, между ними
  стрелка трансформации. Видна в Dock, Finder, Cmd-Tab switcher,
  About panel. Иконка в menu bar остаётся системным mic-глифом
  (один штрих, чище читается на 16-18px).

### Для разработчиков

- `FallbackTranscriptionService` теперь принимает два новых параметра:
  `autoOfflineOnTimeout: Bool` и `autoOfflineTimeoutSeconds: Int`.
  Когда флаг включён, primary-провайдер race-ится против таймера
  через `withThrowingTaskGroup`. Local fallback стартует
  ПОСЛЕДОВАТЕЛЬНО только после `.timeout` или `.primaryFailure(offline)` —
  это обходит то, что `LocalWhisperProvider`'s `Process` continuation
  не реагирует на `Task.cancel()` и иначе блокировал бы возврат
  primary-результата.
- Гард в `TranscriptionCoordinator.fromPreferences`: если provider
  уже `.localWhisper`, тоггл игнорируется (иначе timer на медленной
  локальной транскрипции запустил бы дубликат той же задачи).
- ADR-014 в `decisions.md` с явным acknowledgement tradeoff с ADR-013:
  при включённом тоггле cloud auth/server ошибки (401/403/5xx),
  пришедшие после таймаута, маскируются local-результатом. Принято
  как opt-in компромисс — пользователь сам включил поведение, banner
  `usedOfflineFallback` показывает что переключение произошло.
- 4 новых unit-теста в `FallbackTranscriptionServiceTests.swift`:
  timeout race, primary wins fast, non-offline failure preserves
  error, toggle-off legacy behavior.
- `Preferences.autoOfflineOnTimeout` (Bool, default false) и
  `Preferences.autoOfflineTimeoutSeconds` (Int, default 10).
- L10n строки `autoOfflineOnTimeout` (RU/EN).
- `scripts/make-icns.sh` — конвертит 1024×1024 PNG в `.icns` через
  `sips` + `iconutil`.
- `docs/logo-concepts/` — design exploration: 6 концептов через
  Codex CLI image_generation, chroma-key cleanup через Pillow,
  showcase HTML на разных размерах + menubar mockup.
- `ARCHITECTURE.md` — фикс stale записи о Settings (был
  «SwiftUI TabView», стал `NavigationSplitView` с 0.4.0).

## [0.6.5] — 2026-04-20

### Для пользователей

- **Новый стиль индикатора записи «Студия».** Широкая тёмная панель
  с плотной RMS-волной и колоколообразной огибающей, в стиле
  SuperWhisper. Футер показывает «Stop» + текущий тоггл-хоткей (с fn
  глифом в Fn-режиме). Выбирается в Настройках → Стиль индикатора →
  Студия (широкая панель).

Звуки и поведение транскрипции без изменений относительно 0.6.4/0.6.2.

## [0.6.4] — 2026-04-20

Релиз-откат. Поведение полностью возвращено к 0.6.2.

### Для пользователей

- **Если стояла 0.6.3 — обновитесь до 0.6.4.** Авто-проверка обновлений
  сама это предложит. Версия 0.6.3 изъята (тег и релиз удалены), её
  изменения откачены: расширенный fallback на локальный whisper,
  Studio-панель индикатора, перегенерированные UI-звуки. Studio-стиль
  вернётся отдельно в 0.6.5.
- **Звуки и распознавание** — как в 0.6.2.

## [0.6.2] — 2026-04-16

Security fixes, рефакторинг, library split для тестируемости.

### Для пользователей

- **Приватность:** транскрипты больше не логируются в Console.app.
  Раньше полный текст попадал в системные логи через NSLog.
- **Безопасность:** custom endpoint теперь требует https:// (http
  запрещён, транскрипты не уйдут по открытому каналу).
- **Ошибки видны:** ошибки записи и транскрипции теперь показываются
  баннером в статус-меню. Раньше приложение молча возвращалось в idle.

### Для разработчиков

- `TranscriptionCoordinator.swift` — выделен из MenuBarController.
  Инкапсулирует: выбор провайдера, fallback, context routing, word
  replacements, пост-обработку. MenuBarController: 984→828 строк.
- Library target split: `WhisperHotLib` (.target) + `WhisperHot`
  (.executableTarget) + `WhisperHotTests` (.testTarget). Тесты
  используют `@testable import WhisperHotLib` с реальным production
  кодом (ContextRule, WordReplacement, PostProcessingPreset).
- `AudioRecorder.onRecordingError` callback для поверхностных ошибок.
- WhisperInstaller: stdout handler дренит данные, cancel резюмирует
  continuation.

## [0.6.1] — 2026-04-16

Технический словарь, замены слов, фиксы UI.

### Для пользователей

- **Технический словарь.** Новая секция в настройках: подсказки для
  распознавания (commit, deploy, push...) передаются провайдеру как
  prompt bias. 16 встроенных замен слов (коммит→commit, деплой→deploy,
  кодекс→Codex, гитхаб→GitHub и др.). Редактируются в Settings.
- **Замены применяются до LLM-обработки.** Если STT написал "коммит",
  LLM получит уже "commit" на вход.
- **Установка whisper.cpp** теперь показывает "2-5 мин" в сообщениях.
- **Ручная настройка путей** работает (заменён DisclosureGroup на Toggle).
  Автоматически раскрывается если пути уже настроены.

### Для разработчиков

- `WordReplacement.swift` — модель замены с applyAll(), 16 defaults.
- `Preferences.vocabularyHints` + `wordReplacements` ключи.
- `MenuBarController` передаёт hints как `options.prompt`, применяет
  replacements к `fixedText` (не к `raw.text`).

## [0.6.0] — 2026-04-16

Intent Router, локальная LLM обработка, анимация ожидания для всех
стилей индикатора, офлайн-баннер, unit тесты.

### Для пользователей

- **Intent Router.** Контекстный роутинг теперь читает заголовок окна
  браузера через Accessibility API. Gmail в Chrome автоматически
  получает стиль email, Slack в Safari — casual. Работает без
  скриншотов, только bundle ID + window title.
- **Локальная LLM обработка.** Новый провайдер "Local LLM (llama.cpp)"
  в пост-обработке. Полностью офлайн: запускает llama-cli как
  subprocess. Установите через `brew install llama.cpp` и скачайте
  GGUF модель с HuggingFace.
- **Анимация ожидания.** Все три стиля индикатора (pill, waveform,
  floating capsule) теперь показывают оранжевую пульсирующую
  анимацию во время транскрибации. Раньше индикатор пропадал сразу.
- **Волна побольше.** Floating capsule: 36 баров (было 24), амплитуда
  x8, двойные гармоники для более живого вида.
- **Офлайн-баннер.** Когда WhisperHot использует локальный whisper
  из-за отсутствия интернета, в меню появляется уведомление
  "⚡ Использована локальная транскрипция".
- **Local whisper всегда виден.** Секция Local whisper.cpp теперь
  постоянно отображается внизу таба Providers с toggle.

### Для разработчиков

- `ContextRouter` читает window title через AXUIElement API (lazy query).
- `ContextRule.titleContains` — опциональное поле для title matching.
- `LocalLLMProcessor.swift` — llama-cli subprocess с stdin prompt,
  DispatchGroup EOF tracking, tilde expansion.
- `IndicatorViewModel.Mode` enum (idle/recording/transcribing).
- Все три indicator views обрабатывают transcribing mode.
- `FallbackTranscriptionService` banner через `setPostProcessingError(raw:)`.
- `Tests/WhisperHotTests/ContextRouterTests.swift` — 15 test cases.

## [0.5.0] — 2026-04-16

One-click установка whisper.cpp, авто-переключение на офлайн,
проверка обновлений, иконка приложения, Apache License 2.0.

### Для пользователей

- **Установка whisper.cpp одной кнопкой.** В секции Local whisper.cpp
  кнопка "Установить" запускает `brew install whisper-cpp` и скачивает
  модель ggml-base (~142 МБ) с HuggingFace. Прогресс отображается в
  реальном времени. Ручная настройка путей спрятана в DisclosureGroup.
- **Авто-переключение на офлайн.** Если облачный провайдер недоступен
  (нет интернета), WhisperHot автоматически использует локальный
  whisper.cpp, если он установлен. Пост-обработка тоже пропускается.
- **Проверка обновлений.** Новая секция "Обновления" в Settings.
  Кнопка "Проверить обновления" сверяет версию с GitHub Releases,
  предлагает скачать DMG если есть новая.
- **Иконка приложения.** Микрофон с звуковыми волнами на тёмном
  градиенте. Видна в Dock (при открытии Settings), Finder и About.
- **Apache License 2.0.** Лицензия изменена с MIT на Apache 2.0.

### Для разработчиков

- `LocalSetup/WhisperInstaller.swift` — brew install + HuggingFace
  model download с async pipe draining и progress delegate.
- `Transcription/FallbackTranscriptionService.swift` — wrapper для
  offline fallback (URLError.notConnectedToInternet/networkConnectionLost).
- `LocalSetup/UpdateChecker.swift` — GitHub Releases API с semver
  comparison и 1-hour cache.
- `Resources/WhisperHot.icns` — app icon (1024px, iconutil).

## [0.4.0] — 2026-04-16

Полная замена SuperWhisper: контекстный роутинг, мульти-провайдер
пост-обработка, реверсивный вывод и premium визуал.

### Для пользователей

- **Контекстный роутинг.** WhisperHot определяет, в каком приложении
  ты диктуешь, и автоматически подбирает стиль обработки: Slack получает
  казуальный текст, Mail формальный, VS Code техническую документацию.
  Правила настраиваются в Settings → Post-processing → Context routing.
  По умолчанию 13 предустановленных правил для популярных приложений.
- **Мульти-провайдер пост-обработка.** LLM cleanup теперь работает
  через любой из 4 провайдеров: OpenRouter, OpenAI, Groq, или любой
  OpenAI-совместимый endpoint (Polza.ai и другие агрегаторы). Выбирается
  явно в Settings, API-ключ берётся из Keychain выбранного провайдера.
- **Реверсивный вывод.** Нажми `⌥⌘⇧5` (с Shift) вместо `⌥⌘5`, чтобы
  вставить сырой транскрипт без LLM-обработки. Полезно когда LLM
  переусердствует или нужен дословный текст.
- **Floating capsule.** Новый стиль индикатора записи: капсула с
  blur-эффектом, анимированная waveform на 60 fps через TimelineView,
  пульсирующая красная точка. Включается в Settings → Recording →
  Indicator style.
- **Кастомные звуки.** Три оригинальных тона (start, stop, done)
  вместо системных Morse/Tink/Glass. Если custom звуки не найдены
  в бандле, приложение использует системные как fallback.
- **Polza.ai.** Российский LLM-агрегатор добавлен как именованный
  провайдер для транскрипции и пост-обработки. OpenAI-совместимый
  API, оплата российскими картами.
- **Sidebar навигация.** Настройки переделаны из горизонтальных табов
  в боковую панель (как в System Settings macOS).
- **"WhisperHot" в меню.** При открытии Settings имя приложения
  появляется в строке меню рядом с яблочком, при закрытии исчезает.
- **Русский интерфейс.** Весь UI переведён на русский язык.
  Переключатель языка (русский / английский) в Settings → Запись.

### Для разработчиков

- `ContextRouter/` — новый модуль. `ContextRule` (модель правила) и
  `ContextRouter` (чистая функция resolve: target → preset).
- `LLMPostProcessor` параметризован: endpoint URL, extraHeaders,
  apiKeyProvider как init params. Один класс, 4 провайдера.
- `HotkeyManager` регистрирует 2 Carbon hotkey: primary и raw
  (primary + Shift). Guardrail: если base combo уже содержит Shift,
  raw hotkey не регистрируется.
- `FloatingCapsuleView` — SwiftUI + TimelineView(.animation) + Canvas.
- `SoundPlayer` загружает custom AIFF из app bundle, fallback на
  `/System/Library/Sounds/`.
- `build.sh` копирует `Resources/Sounds/` в `.app` bundle.
- `PostProcessingProvider` enum с endpoint URLs, extraHeaders, и
  Keychain account маппингом.
- `Localization/L10n.swift` — простая enum-based локализация (~150
  строк). Все UI строки через `L10n.*` computed properties.
- `SettingsView` переделан на `NavigationSplitView` (sidebar).
- `SettingsWindowController` переключает activation policy (`.regular`
  при открытии, `.accessory` при закрытии).

## [0.3.0] — 2026-04-16

Переименование WhisperLocal → WhisperHot и переделка menu bar меню.

### Для пользователей

- **Новое имя — WhisperHot.** Всё, что ты видишь: имя в строке
  меню, окна Settings и History, alert'ы, About — теперь говорит
  WhisperHot. Bundle ID стал `com.aleksejsupilin.WhisperHot`, а
  старый `/Applications/WhisperLocal.app` уходит в утиль. Репозиторий
  всегда назывался `whisper-hot`, теперь и приложение совпадает.
- **Статус-меню с контекстом.** Верхняя строка меню теперь показывает,
  какой провайдер активен (и какая модель у него выбрана), плюс
  текущий хоткей. Вторая строка — "Hotkey: ⌥⌘5". Раньше надо было
  открывать Settings, чтобы вспомнить, где ты находишься.
- **Быстрый свитч провайдера прямо из меню.** Новый пункт **Provider ►**
  с четырьмя опциями (OpenAI / OpenRouter / Groq / Local whisper.cpp).
  Текущий помечен галочкой. Выбор пишет preference мгновенно, на
  следующей записи новый провайдер уже активен.
- **History получила шорткат `⌘H`.** Settings остался на `⌘,`,
  Quit — на `⌘Q`. About WhisperHot показывает версию, билд и
  подписывающую identity.
- **Permissions & Onboarding переименован** из "Onboarding &
  Permissions…" — новое имя ставит то, что чаще ищут (Permissions),
  первым.

### Важно при апгрейде

- **macOS видит WhisperHot как новое приложение.** Bundle ID
  изменился, поэтому TCC (Accessibility, Microphone) и Keychain ACL
  надо выдать заново. Один раз. Снеси `/Applications/WhisperLocal.app`,
  поставь `WhisperHot-0.3.0.dmg`, зайди в System Settings → Privacy &
  Security → Accessibility, добавь WhisperHot.
- **Старые Keychain items с префиксом `com.aleksejsupilin.WhisperLocal`
  остаются в связке ключей, но не используются.** Удалить их можно
  вручную через Keychain Access или оставить — WhisperHot под новым
  service name их не трогает.
- **UserDefaults с префиксом `WhisperLocal.*` больше не читаются.**
  Все твои настройки (провайдер, язык, хоткей, история, audio
  retention) сбрасываются до defaults. Зайди в Settings и выстави
  заново.

### Для контрибуторов

- Полный rename по 28 файлам: Package.swift, Resources/Info.plist,
  build.sh, build-dmg.sh, `Sources/WhisperLocal/` → `Sources/WhisperHot/`
  (git mv, 31 файл), `WhisperLocalApp.swift` → `WhisperHotApp.swift`.
  Все строковые константы (Keychain `serviceName`, UserDefaults
  key-префикс, NotificationCenter names, NSLog tags, path components,
  window titles) прошли через `sed s/WhisperLocal/WhisperHot/g +
  s/whisperLocal/whisperHot/g`.
- `MenuBarController.swift` стал `NSMenuDelegate`. Новые поля:
  `headerMenuItem` (disabled status row с `.attributedTitle`),
  `providerSubmenu` (хранится для обновления checkmark'а).
  `menuWillOpen(_:)` вызывает `refreshDynamicMenuState()`, который
  пересчитывает текст хедера и галочку в submenu из
  `Preferences.provider` / `.currentModel` / hotkey values —
  никаких global observer'ов на preference changes.
- `TranscriptionProvider` получил `shortName` computed property
  для компактного отображения в хедере (OpenAI / OpenRouter /
  Groq / Local). Полный `displayName` остаётся в Settings picker'е.
- Внутренний `serviceName` в `Keychain.swift` теперь
  `com.aleksejsupilin.WhisperHot`. История мигрирует per-install:
  старые items не читаются, новые пишутся под новым service.

## [0.2.2] — 2026-04-16

Юзабилити-переделка Settings и исправление regression'ов из 0.2.0.

### Для пользователей

- **Settings теперь в 5 вкладках.** Recording, Providers,
  Post-processing, Hotkey, History & Privacy. Всё, что раньше
  было единой простынёй на 14 секций и не пролистывалось до конца
  (прибитая высота клипала нижние ~600px), теперь разложено по темам.
  Окно настроек стало resizable — можно растянуть или сжать.
- **Хоткей-рекордер наконец-то реально доступен.** Живёт на своей
  вкладке **Hotkey** рядом с кнопкой Reset и экспериментальным
  Fn (🌐) тумблером. Клик в поле → нажимаешь новую комбинацию →
  всё.
- **В Providers видно только выбранный сервис.** Переключаешь
  провайдера — поля чужих API-ключей прячутся. Больше никаких
  трёх параллельных секций OpenAI/OpenRouter/Groq, даже если ты
  используешь только один.
- **Recording → After transcription** явно напоминает про
  Accessibility. Если auto-paste перестал работать (чаще всего
  после апгрейда версии, когда TCC сбрасывает grant'ы), там есть
  подсказка, куда идти в System Settings.

### Для контрибуторов

- `Sources/WhisperLocal/Settings/SettingsView.swift` разобран из
  одного 550-строчного `Form` в 5 отдельных `Form` внутри `TabView`.
  Каждая вкладка — своя `@ViewBuilder` computed property. Прибитый
  `.frame(width: 620, height: 1220)` заменён на
  `minWidth`/`idealWidth`/`maxWidth` + `minHeight`/`idealHeight`/
  `maxHeight`, так что Form с `.formStyle(.grouped)` сам решает, что
  скроллить.
- `SettingsWindowController` теперь создаёт окно с
  `[.titled, .closable, .resizable]`. Initial content size 640×560.
- Поведенческая совместимость сохранена: те же `@AppStorage` ключи,
  тот же `whisperLocalSettingsWillShow` NotificationCenter hook для
  реинициализации Keychain state при повторном открытии, та же
  suppression-flag логика для Launch at login observer.

## [0.2.1] — 2026-04-16

Фикс "Keychain спрашивает пароль на каждую запись после пересборки".
Единственное функциональное изменение — подпись стала стабильной.

### Для пользователей

- **Больше никаких запросов login-пароля на Keychain после первого
  запуска новой версии.** До 0.2.1 каждая пересборка приложения
  меняла designated requirement в code signature, и macOS просил
  разрешения на доступ к API-ключам и ключу шифрования истории на
  каждый rebuild, потому что Keychain ACL был привязан к идентичности
  предыдущего бинаря. 0.2.1 использует стабильный self-signed
  сертификат, так что "Разрешить всегда" прилипает к будущим
  сборкам.
- **Один раз при апгрейде с 0.1.0 / 0.2.0 macOS всё равно спросит
  пароль на каждый уже сохранённый Keychain-item.** Это ожидаемо:
  старый ACL не знает новую identity. Жми **«Разрешить всегда»**
  на каждом диалоге, дальше тихо — и на этой сборке, и на всех
  будущих.
- **Миграция permissions.** Новая identity заново попросит
  Accessibility в System Settings → Privacy & Security → Accessibility.
  TCC не переносит grants с одной подписи на другую, так что
  удалить старый entry и добавить заново — нормальный шаг при
  апгрейде.

### Для контрибуторов

- Новый `scripts/create-signing-identity.sh` генерит self-signed
  RSA 2048 сертификат `whisper-hot-local` с `codeSigning` EKU,
  импортирует его в login keychain через `security import` +
  `set-key-partition-list`, пишет user-domain trust через
  `add-trusted-cert`, и прогоняет end-to-end signing probe
  (компилит stub Mach-O, подписывает новой идентичностью,
  верифицирует через `codesign --verify`). Идемпотентный: если
  идентичность уже существует, запускает только probe. Один раз
  на машине, run-once interactive.
- `build.sh` теперь резолвит identity по CN через
  `security find-identity -p codesigning` и подписывает по SHA-1,
  а не по ad-hoc `--sign -`. Три exit-кода: found / missing /
  duplicates. Отсутствующая identity = hard fail с pointer'ом на
  setup-скрипт. Ad-hoc fallback не предусмотрен специально.
- **Два Apple-specific gotchas**, заархивированные в комментариях
  `scripts/create-signing-identity.sh` шаг [2/7]: OpenSSL 3.x
  требует флага `-legacy` для PBE-SHA1-3DES (иначе `-keypbe`
  тихо игнорируется и файл выходит AES-256), и Apple `security`
  на macOS 13+ отказывается импортировать PKCS#12 с пустым
  passphrase — надо всегда передавать random transport passphrase.
- Новая секция в ARCHITECTURE.md → "Стабильная подпись вместо
  ad-hoc" описывает design-rationale.

## [0.1.0] — 2026-04-15

Первый MVP. 18 запланированных блоков выпущены, каждый проходил
независимое ревью второго мнения (`codex review`) до консенсуса
прежде чем переходить к следующему.

### Для пользователей

- **Голос-в-текст в строке меню.** Иконка микрофона живёт в твоём
  status bar. Жмёшь `⌥⌘5`, говоришь, жмёшь снова. Транскрипт
  попадает в буфер обмена И автоматически вставляется в то
  приложение, в которое ты печатал.
- **Четыре провайдера в picker'е Settings.** OpenAI
  (`gpt-4o-mini-transcribe` / `gpt-4o-transcribe` / `whisper-1`),
  OpenRouter (audio-capable chat модели через
  `/chat/completions`), Groq (`whisper-large-v3-turbo`, примерно
  в 10× быстрее OpenAI напрямую) и локальный whisper.cpp для
  полностью офлайн транскрибации. У каждого провайдера свой слот
  в Keychain, и ты можешь переключаться в любой момент без
  рестарта приложения.
- **Picker языка.** 15 языков плюс auto-detect. Какой бы провайдер
  ты ни использовал, он получит `language` hint.
- **Опциональный LLM cleanup после транскрибации.** Выключен по
  умолчанию. Когда включён, сырой транскрипт уходит через чат-модель
  OpenRouter с одним из пяти встроенных пресетов (Cleanup fillers,
  Email style, Slack casual, Technical documentation, Translate
  to English) или полностью кастомным промптом. Если cleanup step
  падает, ты всё равно получаешь сырой транскрипт — ошибка
  появляется как non-modal banner в status menu и никогда не
  крадёт фокус у целевого приложения.
- **Три стиля индикатора.** Только menubar (иконка микрофона
  пульсирует, никакого дополнительного окна), mini pill (компактная
  капсула с таймером и пульсирующей точкой) и classic waveform
  (более широкая панель с живой визуализацией бар-графика,
  управляемой RMS микрофона). Все три — non-activating floating
  панели, которые переживают переходы Stage Manager, full-screen
  и Spaces.
- **Зашифрованная история транскриптов.** Выключена по умолчанию.
  Когда включена, транскрипты сохраняются в
  `~/Library/Application Support/WhisperLocal/history.bin`,
  зашифрованные at rest через AES-GCM из CryptoKit. 32-байтовый
  ключ генерится при первом использовании и хранится в macOS
  Keychain. Окно истории позволяет скопировать прошлый транскрипт
  одним кликом и стереть всё через confirmation alert. Retention:
  forever / 1 / 7 / 30 / 90 days плюс лимит на количество записей.
- **Политика retention для аудио.** Пять режимов в Settings →
  Privacy & data: Immediate (удалять сразу после успешной
  транскрибации, default и рекомендация), 1 час, 24 часа,
  Until quit (стирается когда WhisperLocal выходит) или Forever.
  Кнопка "Wipe all recorded audio now" чистит всё кроме текущей
  активной записи.
- **Permissions onboarding.** При первом запуске окно проводит
  тебя через grant микрофона и accessibility, поллит состояние
  каждые 2 секунды, чтобы не нужно было рестартить приложение
  после grant'а, и глубоко-линкует в Privacy & Security панели
  Ventura+ с legacy URL fallback для старых macOS. Открывается
  из меню в любой момент.
- **Экспериментальный Fn-key hotkey.** Settings → Hotkey имеет
  toggle "Use Fn (🌐) key instead". Требует Input Monitoring
  permission. Carbon биндинг `⌥⌘5` остаётся живым как fallback
  пока Fn tap реально не запустится, так что ты никогда не
  теряешь keyboard control, даже если macOS ещё не выдала Input
  Monitoring. 3-секундный retry поллит для grant'а без рестарта.
- **Launch at login.** Через `SMAppService.mainApp`. Settings →
  General toggle честно отражает `.enabled` vs `.requiresApproval`
  vs `.notFound`, с remediation-текстом для каждого состояния.
- **Дружелюбные звуки.** Стартовый chime срабатывает когда audio
  engine реально armed, stop chime срабатывает когда ты
  останавливаешь запись, done chime срабатывает после того как
  транскрипт доставлен. Используются встроенные system sounds macOS
  (`Morse`, `Tink`, `Glass`), переключается в Settings.

### Корректность auto-paste

Auto-paste — ключевая фича, поэтому он защищён guards:

- **Snapshot frontmost-app** захватывается при старте записи. Если
  фокус ушёл куда-то ещё к моменту возврата транскрибации,
  транскрипт всё равно копируется в буфер обмена, а меню объясняет
  что случилось. Текст никогда не теряется.
- **Secure input guard.** `IsSecureEventInputEnabled()` блокирует
  auto-paste в password поля, sudo промпты и приложения, которые
  держат Secure Keyboard Input глобально (Terminal в некоторых
  режимах).
- **Проверка Accessibility permission.** Без неё `CGEventPost`
  молча дропает события. WhisperLocal детектит это заранее и
  падает в clipboard-only.
- **Self-check по bundle.** Если WhisperLocal сам frontmost (ты
  кликнул его Settings окно), auto-paste абортится вместо того,
  чтобы вставить текст в Settings.
- **Синтетический Cmd+V** через
  `CGEventSource(stateID: .combinedSessionState)` + `maskCommand`
  на оба keyDown и keyUp, пост в `.cghidEventTap`. Стандартный
  путь для cross-process paste.

### Позиция по приватности

- Default audio retention — "удалять сразу после успешной
  транскрибации". Recording file удаляется в тот же момент, когда
  транскрипт возвращается, если только история не включена И её
  append не упал (тогда сырой WAV остаётся как recovery artifact
  до startup sweep).
- Startup sweep запускается до того как любая запись может начаться
  и чистит остатки от прошлых запусков по сконфигурированной
  retention policy. На `.untilQuit` запуск wipe'ает всё из прошлой
  сессии тоже, так что force-quit не может оставить аудио на
  диске дольше следующего запуска.
- API ключи и ключ шифрования истории пишутся в macOS Keychain с
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` и
  `kSecAttrSynchronizable = false`. Свежие saves не синкаются в
  iCloud Keychain на этой установке.
- Секция Settings → Privacy & data явно проговаривает что уходит
  с Mac: облачные провайдеры видят твоё аудио, clipboard managers
  захватывают транскрипт когда он попадает в pasteboard, а WAV'ы
  живут под `~/Library/Caches/WhisperLocal/recordings/`.

### Для контрибуторов

- **4611 строк Swift** в 31 файле, SwiftPM проект, Swift 5.9,
  таргет macOS 13.0 Ventura.
- **Основная оболочка — AppKit `NSStatusItem`**, SwiftUI через
  `NSHostingView` внутри окон Settings / Onboarding / History и
  в NSPanel'е recording indicator. Смотри ARCHITECTURE.md почему.
- **Audio pipeline** использует `AVAudioEngine` +
  `AVAudioConverter` → 16 kHz mono 16-bit PCM WAV. Real-time tap
  callback захватывает session через `OSAllocatedUnfairLock`,
  диспатчит диск I/O на serial `writerQueue`, а teardown
  использует явный `DispatchGroup` in-flight tracking, так что
  он не зависит от недокументированной семантики barrier'а
  `removeTap`.
- **Transcription providers** делят единый протокол
  `TranscriptionService`. `OpenAICompatibleSTTProvider`
  параметризован endpoint'ом + default моделью + max audio byte
  cap, так что OpenAI и Groq делят один класс. У OpenRouter
  собственный провайдер `input_audio` через chat. Локальный
  whisper.cpp запускает CLI как `Process` subprocess с
  concurrent `readabilityHandler` pipe drains, так что child
  не может повиснуть на переполненном pipe buffer'е.
- **Keychain wrapper** использует `SecItemUpdate` с
  `SecItemAdd` fallback на `errSecItemNotFound`, что избегает
  transient "key missing" окна, которое создавал бы наивный
  delete-then-add. Теперь экспортирует и String (API ключи), и
  raw Data (encryption keys) API.
- **History store** — AES-GCM через CryptoKit со строгим
  key orphan guard: отсутствующий Keychain ключ интерпретируется
  как first use только если `history.bin` тоже не существует.
  Если файл есть, а ключ пропал, store отказывается создавать
  replacement и сурфэйсит чёткое сообщение о том, что делать.
- **Retention sweep** живёт в
  `Privacy/AudioRetentionSweeper.swift` как `@MainActor enum`.
  Уважает свойство `activeRecordingURL`, так что пользователь,
  нажавший "Wipe now" во время записи, не может испортить
  собственную активную сессию. Shutdown wipe для `.untilQuit`
  явно перекрывает этот guard через параметр
  `includingActive: true` — смысл политики именно в том, чтобы
  ничего не оставалось на exit.
- **Build output живёт вне iCloud-синкаемого дерева проекта**
  потому что File Provider переклеивает
  `com.apple.FinderInfo` и `com.apple.fileprovider.fpfs#P`
  xattrs быстрее чем `xattr -cr` успевает их снять. Сборка
  происходит в `~/Library/Caches/WhisperLocal-build/`.
- **DMG упаковка** через `hdiutil create` с `UDZO` +
  `zlib-level=9` + `HFS+`. Staging директория — `mktemp -d` с
  `EXIT` trap, так что прерванные сборки не оставляют
  полузаполненные stages. `BUILD_OUT_DIR` env-overridable, но
  case-matched против безопасного allow-list
  (`$HOME/Library/Caches/*`, `/tmp/*`, `/private/tmp/*`) до
  того как на нём запустится `rm -rf`.

### Известные ограничения

- Хоткей зашит как `⌥⌘5` в 0.1.0. Рекордер UI для кастомных
  комбинаций отложен.
- Ad-hoc подписан, не нотаризован. Первый запуск всегда требует
  right-click → Open. Developer ID подпись отложена.
- `.untilQuit` retention — best-effort. Kernel panic или
  force-kill оставит аудио на диске до startup sweep на следующем
  запуске.
- Только Apple Silicon. Intel Mac build не был целью MVP.
