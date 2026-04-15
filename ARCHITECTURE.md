# Архитектура

WhisperLocal — это Swift 5.9 / SwiftPM macOS приложение. 32 Swift
файла, ~5100 строк. AppKit — основная оболочка, SwiftUI живёт внутри
Settings, Onboarding, History и recording indicator через
`NSHostingView`.

## Почему AppKit, а не MenuBarExtra

Первая редакция плана тянулась к SwiftUI `MenuBarExtra` и SwiftUI
settings scene. Ревизия перешла на AppKit `NSStatusItem`, потому что:

1. Recording indicator — это non-activating floating `NSPanel` с
   специфичными флагами `collectionBehavior` (`canJoinAllSpaces`,
   `stationary`, `fullScreenAuxiliary`). MenuBarExtra не даёт
   такого уровня контроля над окнами.
2. Settings и Onboarding окна должны сохранять фокус на приложении,
   в которое ты диктовал. Для этого нужен ручной захват
   `previousApp = NSWorkspace.shared.frontmostApplication` и явный
   `.activate(options: [])` на close. SwiftUI scenes крадут фокус
   агрессивно и неудобны для такой задачи.
3. Block 5 auto-paste зависит от того, что WhisperLocal НИКОГДА не
   становится frontmost во время транскрибации. `LSUIElement = true`
   плюс обычный `NSStatusItem` — самая надёжная оболочка для этого.

SwiftUI всё равно используется для всего реального UI внутри этих
окон. Внешний контейнер — AppKit, содержимое — SwiftUI.

## Карта модулей

```
Sources/WhisperLocal/
├── WhisperLocalApp.swift         @main entry point; регистрирует defaults
├── AppDelegate.swift             NSApplication lifecycle; retention hooks
├── MenuBarController.swift       Status item, state machine, фабрика провайдеров
│
├── Audio/
│   ├── AudioError.swift
│   ├── AudioRecorder.swift       AVAudioEngine → 16 kHz mono PCM WAV
│   └── SoundPlayer.swift         AudioServicesPlaySystemSound chimes
│
├── Hotkey/
│   ├── HotkeyManager.swift       Carbon RegisterEventHotKey (⌥⌘5 default)
│   └── FnKeyMonitor.swift        CGEventTap на maskSecondaryFn (opt-in)
│
├── Transcription/
│   ├── TranscriptionService.swift  Протокол + TranscriptionOptions + result
│   ├── TranscriptionError.swift
│   └── Providers/
│       ├── OpenAICompatibleSTTProvider.swift  OpenAI + Groq
│       ├── OpenRouterAudioProvider.swift       Chat completions with audio
│       └── LocalWhisperProvider.swift          whisper.cpp subprocess
│
├── PostProcessing/
│   ├── PostProcessingPreset.swift  Cleanup, email, Slack, technical, ...
│   └── LLMPostProcessor.swift      OpenRouter /chat/completions (text only)
│
├── Paste/
│   └── PasteService.swift        Pasteboard write + guarded CGEventPost
│
├── Permissions/
│   ├── PermissionsCoordinator.swift  Mic, AX, Input Monitoring
│   └── OnboardingWindowController.swift  First-run window
│
├── Settings/
│   ├── Preferences.swift         UserDefaults ключи + типизированные accessors
│   └── SettingsView.swift        SwiftUI TabView (5 вкладок) внутри NSHostingView
│
├── SettingsWindowController.swift  NSWindow host для SettingsView
│
├── Indicator/
│   ├── IndicatorController.swift   NSPanel owner; читает Preferences
│   ├── IndicatorViewModel.swift    20 Hz RMS + elapsed publisher
│   ├── MiniPillView.swift          Capsule с pulse dot
│   └── ClassicWaveformView.swift   Canvas bar renderer
│
├── Keychain/
│   └── Keychain.swift            String + Data API, не-синкаемые items
│
├── History/
│   ├── TranscriptRecord.swift    Плоский Codable model
│   ├── HistoryStore.swift        AES-GCM файл + key orphan guard
│   └── HistoryWindowController.swift  SwiftUI List через NSHostingView
│
├── LaunchAtLogin/
│   └── LaunchAtLoginController.swift  SMAppService.mainApp wrapper
│
└── Privacy/
    └── AudioRetentionSweeper.swift    Startup sweep + shutdown wipe
```

## Data flow: одна полная запись

```
Пользователь жмёт ⌥⌘5
   │
   ▼
HotkeyManager (Carbon) → onHotkey (синхронно, main thread)
   │
   ▼
MenuBarController.toggleRecording
   │  state: .idle → .recording
   │  захватывает frontmostApplication в `recordingTarget`
   │  ставит AudioRetentionSweeper.activeRecordingURL = url
   │  играет стартовый chime
   ▼
AudioRecorder.startRecording
   │  AVAudioEngine.inputNode.installTap (real-time thread)
   │    └→ AVAudioConverter → 16 kHz mono Int16 PCM
   │         └→ writerQueue.async → AVAudioFile.write
   │  tapGroup.enter/leave для учёта in-flight callback'ов
   │  OSAllocatedUnfairLock на session + RMS
   ▼
Пользователь говорит. IndicatorViewModel поллит currentRMS на 20 Hz.
   │
   ▼
Пользователь жмёт ⌥⌘5 снова
   │
   ▼
MenuBarController.stopRecordingFromMenu
   │  играет stop chime
   ▼
AudioRecorder.stopRecording
   │  removeTap; tapGroup.wait; writerQueue.sync {}
   │  clear session; возвращает WAV URL
   ▼
MenuBarController.kickOffTranscription
   │  state: .recording → .transcribing
   │  строит service через makeTranscriptionService(for: Preferences.provider)
   │  снапшотит PostProcessingOptions + LLMPostProcessor если включён
   │
   │  Task.detached:
   │   ├─ service.transcribe(url, options)  [network / subprocess]
   │   ├─ опциональный postProcessor.process(raw.text) [network]
   │   └─ await self?.finishTranscription(outcome:)   [main actor hop]
   │
   ▼
MenuBarController.finishTranscription (main actor)
   │  state: .transcribing → .idle
   │
   ├─ .success:
   │   ├─ Preferences.autoPaste → PasteService.deliver
   │   │    (focus guard, secure-input guard, CGEventPost Cmd+V)
   │   ├─ иначе pasteboard-only write
   │   ├─ playChimeIfEnabled(.done)
   │   ├─ Preferences.historyEnabled → historyStore.append
   │   ├─ Preferences.audioRetention == .immediate AND history OK
   │   │    → AudioRetentionSweeper.delete(url)
   │   └─ postProcessing .failed → setPostProcessingError banner
   │
   └─ .failure:
       └─ только NSLog; WAV остаётся для ретрая
```

## Threading model

- **Main thread.** Весь lifecycle, state machine, hotkey callbacks,
  UI updates, управление NSPanel, Settings, Keychain reads.
- **Real-time audio thread.** Callback от
  `AVAudioEngine.inputNode.installTap`. Захватывает session через
  `OSAllocatedUnfairLock` (разовый снапшот, локи не держатся на
  I/O), запускает `AVAudioConverter` в свежий `AVAudioPCMBuffer`,
  диспатчит реальный `AVAudioFile.write` на serial `writerQueue`.
- **writerQueue.** Serial dispatch queue с QoS `userInitiated`.
  Весь диск I/O для записи происходит здесь, чтобы audio thread
  никогда не блокировался на filesystem-стоппере. `stopRecording`
  дренит её через `writerQueue.sync {}` после ожидания `tapGroup`
  для in-flight callback'ов.
- **Task.detached (транскрибация).** Background concurrency domain
  для network upload + сборки multipart + опционального
  post-processing. Никогда не на main. Возвращает результаты на main
  через `await self?.finishTranscription(outcome:)`.
- **Carbon event handler.** Только для Fn key path. Работает на
  main runloop потому что мы добавляем `CGEventTap` source в
  `CFRunLoopGetMain()`. Триггерит `onFnKeyPressed` синхронно.
- **NotificationCenter observer queues.** Config change для
  `AVAudioEngineConfigurationChange` слушает на main. Observer
  UserDefaults changes для Fn-key toggle слушает на main.
- **Process.terminationHandler.** Для `LocalWhisperProvider`.
  Работает на private dispatch queue. Читает дренированные данные
  из буферов, защищённых `DispatchGroup`, и резьюмит continuation.

## Ключевые design-решения

### Transcription provider factory per-call, не per-app

`MenuBarController.makeTranscriptionService(for:)` создаёт свежий
объект провайдера каждый раз, когда запись останавливается. Это
позволяет пользователю переключить провайдера в Settings и
использовать новый на следующей же записи — без рестарта, без
observer'ов. Объекты провайдеров дёшевы в создании (пара closure'ов
и endpoint URL), так что трейд целиком в плюс.

### Плоская post-processing provenance в TranscriptRecord

`PostProcessingOutcome` — sealed enum внутри TranscriptionResult
(`.succeeded(model, preset)` / `.failed(reason)` / nil). Но когда
он попадает в `TranscriptRecord` для хранения в истории, три
состояния разворачиваются в nullable flat поля:
`postProcessingModel` / `postProcessingPreset` / `postProcessingFailed`
/ `postProcessingFailureReason`.

Обоснование: Codable enum synthesis хрупок к schema evolution.
Плоские nullable поля лучше переживают добавление кейсов,
переименования и миграции формата, чем sealed-enum Codable blob.

### Audio retention задан приложением, не провайдером

`OpenAICompatibleSTTProvider` принимает `maxAudioBytes` в init.
И OpenAI, и Groq сейчас уходят на 25 MB — это hard limit OpenAI и
предел free tier Groq. Dev tier Groq выше (100 MB + URL upload для
больших файлов), но default остаётся консервативным.
`OpenRouterAudioProvider` ограничен 8 MB потому что OpenRouter не
публикует ceiling и возвращает 413 на oversized chat requests.

Cap бросает `TranscriptionError.audioFileTooLarge` ДО какого-либо
base64 encoding или сборки multipart. Fail fast, не трать CPU на
загрузки, которые провайдер отклонит.

### Carbon fallback остаётся живым пока Fn пытается стартовать

`MenuBarController.syncHotkeyBindings` СНАЧАЛА пробует
`fnKeyMonitor.start()` когда пользователь включает toggle. Только
на успехе он делает `hotkeyManager.unregister()` Carbon. На
неудаче он вызывает `hotkeyManager.register()`, чтобы Carbon был
живым как fallback, и поднимает 3-секундный retry timer
(`fnRetryTimer`, `tolerance = 1.0`), который поллит пока Fn не
поднимется или пока пользователь не выключит toggle.

Пользователь никогда не остаётся без работающего keyboard trigger.
Это инвариант.

### Зашифрованная история отказывается осиротить ciphertext

`HistoryStore.encryptionKey()` строго обрабатывает "first use"
detection. Отсутствующий Keychain item интерпретируется как
first-use ТОЛЬКО если `history.bin` тоже не существует. Если файл
есть, а ключ пропал, метод бросает `HistoryError.decryptionFailed`
с remediation текстом, указывающим на Settings → History → Clear
all. Он никогда не создаёт молча replacement ключ, который оставил
бы старый зашифрованный файл un-decryptable.

### Stage manager и multi-display индикатор

`IndicatorController.positionOnScreen` использует
`NSScreen.main ?? NSScreen.screens.first`, потому что
`NSScreen.main` отслеживает экран key window активного приложения
и может быть nil. `collectionBehavior` панели —
`[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`
так что она переживает переходы между Spaces и full-screen.
Точное позиционирование эвристическое ("top-center видимой
области, 12pt ниже menu bar"), не идеальное под Stage Manager,
но корректное для общего случая.

### Стабильная подпись вместо ad-hoc

До 0.2.1 `build.sh` подписывал `.app` ad-hoc (`codesign --sign -`).
Ad-hoc identity выводится из code-directory-хэша бинаря, поэтому
каждая пересборка давала новый designated requirement. Все
Keychain items, ACL которых трастил предыдущую идентичность,
начинали выпрашивать login-пароль на каждый доступ. Та же проблема
и с TCC grants (Accessibility, Microphone): смена подписи = новое
приложение в глазах macOS.

0.2.1+ подписывается стабильным self-signed сертификатом
`whisper-hot-local` из login keychain пользователя. SHA-1 cert'а
фиксирован между пересборками, так что после одного клика
"Always Allow" на первом запуске новой идентичности все последующие
сборки молчат. Сертификат создаётся однократно через
`scripts/create-signing-identity.sh` — идемпотентный скрипт, который
генерит RSA 2048 + self-signed X.509 с `extendedKeyUsage codeSigning`,
заливает его через `security import` + `set-key-partition-list`,
пишет user-domain trust через `add-trusted-cert`, и прогоняет
end-to-end signing probe (компилит stub Mach-O, подписывает,
верифицирует). Любая ошибка на любом шаге валит скрипт.

`build.sh` резолвит identity через `security find-identity -p
codesigning` по CN. Если identity отсутствует или найдены
дубликаты — скрипт падает с инструкцией запустить one-shot setup.
Ad-hoc fallback не предусмотрен специально: тихий откат на ad-hoc
был бы именно тем регрессом, от которого мы ушли.

Два макОС-specific gotchas зашиты в комментарии
`scripts/create-signing-identity.sh` шаг [2/7]:

1. OpenSSL 3.x держит PBE-SHA1-3DES / RC2 / MD5 за "legacy provider",
   который не загружен по умолчанию. Без `-legacy` флага
   `-keypbe`/`-certpbe` тихо игнорируются, и файл выходит
   AES-256-CBC + SHA-256, который Apple `security import` не
   понимает.
2. Apple `security` на macOS 13+ отвергает PKCS#12 с пустым
   passphrase, выдавая `MAC verification failed during PKCS12
   import (wrong password?)`, даже если формат правильный. Скрипт
   генерит случайный transport passphrase через `openssl rand -hex`,
   передаёт в обе команды, и отпускает его с tempdir'ом.

### iCloud-safe build output

`build.sh` собирает `.app` bundle под
`~/Library/Caches/WhisperLocal-build/`, не под `./build/` в корне
проекта. Причина: проект живёт в `~/Documents`, который синкается
iCloud Drive. File Provider переклеивает
`com.apple.FinderInfo` и `com.apple.fileprovider.fpfs#P` xattrs к
файлам в iCloud-синкаемых директориях быстрее чем `xattr -cr`
может их снять, и `codesign` отказывается подписывать что-либо
с такими xattrs на месте. Перемещение вывода за пределы
синкаемого дерева — единственный надёжный фикс.

## Остаточные риски

Задокументированы в `whisper.md` §14 и подняты в codex review, но
не блокеры для 0.1.0:

- **Focus TOCTOU на paste.** Всегда есть микроскопическое окно
  между focus-check в `PasteService.deliver` и реальным
  `CGEventPost`. Нормальные race деградируют до clipboard-only.
  Убрать в приложении нельзя.
- **`.untilQuit` на force-quit.** `applicationWillTerminate` не
  срабатывает на force-quit или краше. Startup sweep на следующем
  запуске подхватывает остатки файлов (Block 18 добавил явный
  `.untilQuit` launch wipe для этого случая).
- **Per-tap AVAudioPCMBuffer allocation.** Не real-time perfect,
  но voice recorder на 16 kHz mono имеет достаточно низкий
  data rate, чтобы давление аллокаций не было измеримым.
- **Позиционирование под Stage Manager / multi-display.**
  Эвристическое, не pixel-perfect.
- **BTM / Login Items state при смене install-пути.** Apple
  документирует, что Login Items cleanup задержан. Dev-mode
  тестирование `SMAppService` из `~/Library/Caches/` — шум.

## Версия

Единый источник правды для shipping версии —
`Resources/Info.plist` → `CFBundleShortVersionString`. Верхнеуровневый
файл `VERSION` дублирует её для удобства tooling. `build-dmg.sh`
читает значение из Info.plist через `plutil -extract` и называет
DMG как `WhisperLocal-<version>.dmg`.
