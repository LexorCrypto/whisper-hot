# WhisperLocal

Локальное macOS-приложение в строке меню, которое записывает твой голос,
транскрибирует его через выбранного провайдера и вставляет текст в то
приложение, где ты сейчас печатаешь. Жмёшь `⌥⌘5`, говоришь, снова жмёшь
`⌥⌘5`, транскрипт оказывается у курсора.

Статус: **0.1.0** — первый MVP, ad-hoc подписан, собран одним разработчиком.

## Что делает

- Живёт только в menu bar. Нет иконки в Dock, нет полноэкранного окна.
  Просто микрофон рядом с часами.
- `⌥⌘5` начинает и останавливает запись. Стартовый chime срабатывает,
  когда audio engine реально armed, так что тишина в первые 200ms —
  нормально, можно говорить сразу.
- Плавающий индикатор показывает elapsed time и живой RMS-уровень во
  время записи. Три стиля: menubar-only, mini pill, classic waveform.
  Переключается в настройках.
- Когда останавливаешь запись, WAV уходит выбранному STT-провайдеру.
  Возвращённый текст кладётся в буфер обмена И автоматически вставляется
  в активное приложение через синтетический `Cmd+V`, если ты не выключил
  auto-paste.
- Опциональный LLM cleanup после транскрибации: удаление филлеров,
  пунктуация, переформатирование в стиль email / Slack / техдок.
- Опциональная зашифрованная история прошлых транскриптов, по умолчанию
  выключена.

## Провайдеры

| Провайдер | API | Модель по умолчанию | Офлайн | Примечание |
|-----------|-----|---------------------|--------|------------|
| OpenAI | `/v1/audio/transcriptions` | `gpt-4o-mini-transcribe` | Нет | Максимальная точность, самый дорогой. |
| OpenRouter | `/v1/chat/completions` с `input_audio` | `openai/gpt-4o-audio-preview` | Нет | Один ключ, много audio-capable chat моделей. |
| Groq | `/openai/v1/audio/transcriptions` | `whisper-large-v3-turbo` | Нет | Примерно в 10× быстрее и сильно дешевле OpenAI. |
| Local whisper.cpp | Subprocess к локальному бинарю | Любой GGML файл, путь к которому ты задашь | **Да** | Полностью офлайн. Ключ не нужен. |

Провайдер меняется в настройках в любой момент. Для каждого свой слот
API-ключа в Keychain, приложение подтягивает правильный при вызове
транскрибации.

## Установка

1. Скачай `WhisperLocal-0.1.0.dmg`.
2. Открой DMG, перетащи `WhisperLocal.app` на ярлык Applications, размонтируй.
3. Первый запуск из `/Applications/WhisperLocal.app` упрётся в Gatekeeper
   (сборка ad-hoc подписана, не нотаризована). Правый клик по приложению,
   выбери **Open**, подтверди один раз. После этого macOS запомнит.
4. Иконка микрофона появится в menu bar, справа сверху. Если у тебя
   MacBook с notch и забитый menu bar, иконка может быть скрыта за
   notch'ем. Перетащи другие menu-bar иконки влево зажав Cmd, чтобы
   освободить место, или поставь менеджер типа Ice / Hidden Bar.

## Первый запуск

На первом запуске увидишь окно **Onboarding & Permissions** с двумя
строками:

- **Microphone** — обязательно. Клик по Request Access, macOS покажет
  системный промпт, жмёшь Allow.
- **Accessibility** — обязательно для auto-paste в другие приложения.
  Клик Open Settings, включи WhisperLocal в Privacy & Security →
  Accessibility. Окно онбординга опрашивает состояние каждые 2 секунды,
  перезапускать приложение после grant'а не нужно.

Когда обе строки зелёные, жми Done. Окно потом можно переоткрыть из
меню (`Onboarding & Permissions…`).

Прежде чем первая запись реально заработает, открой **Settings**, вставь
OpenAI API-ключ (или OpenRouter / Groq — что выбрал в Provider picker),
жми Save. Ключи живут в macOS Keychain, не в UserDefaults, не синкаются
в iCloud.

## Как пользоваться

1. Поставь курсор в целевое текстовое поле (Slack, Messages, Notes,
   терминал, что угодно).
2. Жмёшь `⌥⌘5`. Слышишь стартовый chime. Появляется индикатор.
3. Говоришь.
4. Жмёшь `⌥⌘5` снова. Слышишь стоп-chime. Пункт меню меняется на
   "Transcribing…", точка в статус-баре продолжает пульсировать.
5. Через пару секунд транскрипт у тебя в буфере обмена И уже вставлен
   в курсор. Слышишь done chime.

Если auto-paste не прошёл guards (фокус изменился, secure input field,
Accessibility не выдан, WhisperLocal сам стал frontmost), транскрипт
всё равно в буфере, а в меню появляется строка с объяснением что
случилось. Текст не теряется никогда.

## Настраиваемые штуки

Всё через **Settings…** в menu bar:

- **General** — Launch at login (через `SMAppService.mainApp`).
- **Provider** — OpenAI / OpenRouter / Groq / Local whisper.cpp.
- **API keys** — отдельные Keychain слоты для OpenAI, OpenRouter, Groq.
  Local whisper.cpp вместо ключа требует путь к бинарю + путь к GGML
  модели.
- **Transcription** — выбор модели под провайдера, выбор языка
  (auto + 15 языков).
- **After transcription** — тумблер auto-paste, тумблер звуковых
  сигналов.
- **Indicator** — menubar-only / mini pill / classic waveform.
- **Hotkey** — `⌥⌘5` зашит в 0.1.0. Доступен экспериментальный opt-in
  на Fn (🌐) клавишу, но это хрупко потому что macOS резервирует Fn
  под Dictation / Show Emoji.
- **Post-processing** — опциональный LLM cleanup с пресетами
  (Cleanup, Email style, Slack casual, Technical docs,
  Translate to English, Custom). Использует твой OpenRouter ключ.
- **Privacy & data** — retention для аудио (Immediate / 1h / 24h /
  Until quit / Forever), явная кнопка Wipe, раскрытие того что
  уходит с твоего Mac.
- **History** — выключена по умолчанию. Когда включена, транскрипты
  идут в AES-GCM зашифрованный файл в
  `~/Library/Application Support/WhisperLocal/`. Retention:
  forever / 1 / 7 / 30 / 90 days плюс лимит на количество записей.

## Приватность

- **Аудиофайлы** живут в `~/Library/Caches/WhisperLocal/recordings/`
  как 16 kHz mono 16-bit WAV. Retention по умолчанию:
  "удалять сразу после успешной транскрибации". Startup sweep
  чистит остатки от прошлых запусков (например, транскрибацию,
  которая упала на середине загрузки).
- **Облачные провайдеры** (OpenAI, OpenRouter, Groq) получают твоё
  аудио по HTTPS. Local whisper.cpp запускается subprocess'ом на
  твоём Mac и ничего не шлёт по сети.
- **Менеджеры буфера обмена** (Paste, Raycast, Alfred, ...) захватят
  транскрипт когда он попадёт в pasteboard. Выключи auto-paste если
  это критично.
- **API ключи** и ключ шифрования истории живут в macOS Keychain,
  записаны с `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` и
  `kSecAttrSynchronizable = false`, так что свежие записи не
  синкаются в iCloud.
- **Шифрование истории** использует AES-GCM через CryptoKit.
  32-байтовый ключ генерится при первом использовании, хранится
  в Keychain, никогда не экспортируется. Если ключ потерян, но файл
  истории ещё существует, приложение откажется создавать новый ключ
  и попросит тебя wipe историю вместо того чтобы молча осиротить
  старый ciphertext.

## Сборка из исходников

Нужны Xcode Command Line Tools (macOS SDK и `swift` CLI). Полный
Xcode.app НЕ требуется.

```bash
./build.sh
```

Запускает `swift build -c release` и собирает подписанный `.app`
bundle в `~/Library/Caches/WhisperLocal-build/WhisperLocal.app`.
Вывод сборки лежит вне iCloud-синкаемого дерева проекта специально:
File Provider переприклеивает `com.apple.FinderInfo` и
`com.apple.fileprovider.fpfs#P` xattrs к файлам под `~/Documents/`
быстрее чем `xattr -cr` может их снять, и `codesign` отказывается
подписывать что-либо с такими xattrs на месте.

Для сборки DMG:

```bash
./build-dmg.sh
```

Пишет `WhisperLocal-0.1.0.dmg` рядом с .app.

## Известные ограничения 0.1.0

- Хоткей зашит как `⌥⌘5`. Рекордера для смены пока нет.
- Ad-hoc подписан, не нотаризован. Первый запуск всегда требует
  right-click → Open. Developer ID подпись + нотаризация отложены.
- `.untilQuit` audio retention работает по принципу best-effort.
  Force-quit или краш пропускают `applicationWillTerminate`, и
  cleanup делает startup sweep на следующем запуске.
- Pasteboard restore не реализован. Когда транскрипт попадает в
  твой буфер обмена, он там остаётся до следующего копирования.
- Нет streaming транскрибации. Весь WAV заливается после того как
  ты остановил запись.
- Иконка menu bar может быть скрыта за notch'ем на MacBook'ах с
  забитым menu bar. Поставь менеджер menu bar если это твой случай.
- Только Apple Silicon (arm64). Поддержка Intel Mac не входила в
  цели MVP.

## Архитектура

Смотри [`ARCHITECTURE.md`](ARCHITECTURE.md) для карты модулей,
data flow и ключевых решений, которые определили кодовую базу.

## Changelog

Смотри [`CHANGELOG.md`](CHANGELOG.md).

## Лицензия

Личный проект. Лицензия не декларирована. Если хочешь переиспользовать
код — сначала спроси.
