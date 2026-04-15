# Changelog

Все значимые изменения в WhisperLocal.

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
