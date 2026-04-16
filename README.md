# WhisperHot

Локальное macOS-приложение в строке меню, которое записывает твой голос,
транскрибирует его через выбранного провайдера и вставляет текст в то
приложение, где ты сейчас печатаешь. Жмёшь `⌥⌘5`, говоришь, снова жмёшь
`⌥⌘5`, транскрипт оказывается у курсора.

Статус: **0.5.0** — personal build. Подписан стабильным локальным
self-signed сертификатом (`whisper-hot-local`), не нотаризован,
собран одним разработчиком. 0.4.0 добавляет контекстный роутинг,
мульти-провайдер пост-обработку, реверсивный вывод и premium визуал.

## Что делает

- Живёт только в menu bar. Нет иконки в Dock, нет полноэкранного окна.
  Просто микрофон рядом с часами.
- `⌥⌘5` начинает и останавливает запись. Стартовый chime срабатывает,
  когда audio engine реально armed, так что тишина в первые 200ms —
  нормально, можно говорить сразу.
- Плавающий индикатор показывает elapsed time и живой RMS-уровень во
  время записи. Четыре стиля: menubar-only, mini pill, classic waveform,
  floating capsule (premium, с blur-эффектом и анимированной waveform).
  Переключается в настройках.
- Когда останавливаешь запись, WAV уходит выбранному STT-провайдеру.
  Возвращённый текст кладётся в буфер обмена И автоматически вставляется
  в активное приложение через синтетический `Cmd+V`, если ты не выключил
  auto-paste.
- Опциональный LLM cleanup после транскрибации: удаление филлеров,
  пунктуация, переформатирование в стиль email / Slack / техдок.
  Поддерживает 4 LLM-провайдера: OpenRouter, OpenAI, Groq, любой
  OpenAI-совместимый endpoint (Polza.ai и др.).
- Контекстный роутинг: автоматически подбирает стиль обработки по
  активному приложению (Slack = казуально, Mail = формально, VS Code =
  техдокументация). Правила настраиваются.
- `⌥⌘⇧5` (с Shift) вставляет сырой текст без LLM-обработки.
- Установка whisper.cpp одной кнопкой (Homebrew + модель с HuggingFace).
  Если нет интернета, автоматически переключается на локальную
  транскрипцию.
- Проверка обновлений прямо из настроек (GitHub Releases API).
- Опциональная зашифрованная история прошлых транскриптов, по умолчанию
  выключена.

## Провайдеры

| Провайдер | API | Модель по умолчанию | Офлайн | Примечание |
|-----------|-----|---------------------|--------|------------|
| OpenAI | `/v1/audio/transcriptions` | `gpt-4o-mini-transcribe` | Нет | Максимальная точность, самый дорогой. |
| OpenRouter | `/v1/chat/completions` с `input_audio` | `openai/gpt-4o-audio-preview` | Нет | Один ключ, много audio-capable chat моделей. |
| Groq | `/openai/v1/audio/transcriptions` | `whisper-large-v3-turbo` | Нет | Примерно в 10× быстрее и сильно дешевле OpenAI. |
| Polza.ai | `/v1/audio/transcriptions` (OpenAI-совместимый) | `gpt-4o-mini-transcribe` | Нет | Российский LLM-агрегатор. Оплата российскими картами. |
| Local whisper.cpp | Subprocess к локальному бинарю | Любой GGML файл, путь к которому ты задашь | **Да** | Полностью офлайн. Ключ не нужен. |

Провайдер меняется в настройках в любой момент. Для каждого свой слот
API-ключа в Keychain, приложение подтягивает правильный при вызове
транскрибации.

## Установка

> **Требования:** macOS 13.0 Ventura или новее, процессор Apple Silicon (M1 и новее).
> Intel Mac не поддерживается.

1. Скачай последнюю версию: [**WhisperHot.dmg**](https://github.com/LexorCrypto/whisper-hot/releases/latest)
2. Открой DMG, перетащи `WhisperHot.app` на ярлык Applications, размонтируй.
3. **Перед первым запуском** сними карантинный атрибут в Терминале:
   ```
   xattr -cr /Applications/WhisperHot.app
   ```
   Без этого macOS Sequoia предложит удалить приложение (сборка
   self-signed, не нотаризована). После `xattr -cr` приложение
   запускается нормально навсегда.
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
  Клик Open Settings, включи WhisperHot в Privacy & Security →
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
Accessibility не выдан, WhisperHot сам стал frontmost), транскрипт
всё равно в буфере, а в меню появляется строка с объяснением что
случилось. Текст не теряется никогда.

## Настраиваемые штуки

Всё через **Settings…** в menu bar. Настройки разбиты на
5 секций с боковой навигацией (sidebar). При открытии Settings
"WhisperHot" появляется в меню приложения рядом с яблочком,
при закрытии исчезает. Интерфейс на русском и английском
(переключается в Settings → Запись → Язык интерфейса).

- **Recording** — язык (auto + 15 языков), auto-paste в активное
  приложение, звуковые chimes, стиль индикатора
  (menubar-only / mini pill / classic waveform / floating capsule),
  Launch at login через `SMAppService.mainApp`.
- **Providers** — один picker сверху выбирает сервис (OpenAI /
  OpenRouter / Groq / Polza.ai / Local whisper.cpp). Ниже
  показываются только поля выбранного провайдера: API-ключ +
  model picker, либо пути к `whisper.cpp` бинарю + GGML модели
  для локального режима. У каждого провайдера свой слот в Keychain,
  переключение не требует рестарта.
- **Post-processing** — тумблер LLM cleanup после транскрибации,
  выбор провайдера (OpenRouter / OpenAI / Groq / Polza.ai / custom endpoint),
  выбор пресета (Cleanup fillers, Email style, Slack casual,
  Technical docs, Translate to English, Custom), контекстный роутинг
  (автовыбор пресета по активному приложению), и `⌥⌘⇧5` для raw
  output без обработки. Выключено по умолчанию.
- **Hotkey** — кастомный рекордер (`⌥⌘5` по умолчанию, кнопка
  Reset возвращает его). Рядом экспериментальный Fn (🌐) тумблер:
  хрупко, потому что macOS резервирует Fn под Dictation / Show
  Emoji, но если Input Monitoring выдан — работает.
- **History & Privacy** — тумблер локальной истории транскриптов
  (выключен по умолчанию; когда включён, AES-GCM в
  `~/Library/Application Support/WhisperHot/history.bin`
  с retention forever / 1 / 7 / 30 / 90 days и лимитом записей),
  retention для сырого аудио (Immediate / 1h / 24h / Until quit /
  Forever), кнопка Wipe всего аудио, сводка приватности.

## Приватность

- **Аудиофайлы** живут в `~/Library/Caches/WhisperHot/recordings/`
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

Нужны Xcode Command Line Tools (macOS SDK, `swift` CLI, `cc`).
Полный Xcode.app НЕ требуется.

**Один раз на машину** — создать стабильную codesigning identity:

```bash
./scripts/create-signing-identity.sh
```

Скрипт интерактивный: спросит твой macOS логин-пароль один раз,
сгенерит self-signed сертификат `whisper-hot-local` в login keychain
и прогонит end-to-end signing probe. Без этого `build.sh` откажется
собирать. Почему так — см. ARCHITECTURE.md → "Стабильная подпись
вместо ad-hoc".

Дальше обычная сборка:

```bash
./build.sh
```

Запускает `swift build -c release` и собирает подписанный `.app`
bundle в `~/Library/Caches/WhisperHot-build/WhisperHot.app`.
Вывод сборки лежит вне iCloud-синкаемого дерева проекта специально:
File Provider переприклеивает `com.apple.FinderInfo` и
`com.apple.fileprovider.fpfs#P` xattrs к файлам под `~/Documents/`
быстрее чем `xattr -cr` может их снять, и `codesign` отказывается
подписывать что-либо с такими xattrs на месте.

Для сборки DMG:

```bash
./build-dmg.sh
```

Пишет `WhisperHot-<version>.dmg` рядом с .app (сейчас
`WhisperHot-0.3.0.dmg`).

## Известные ограничения

- Подпись — локальный self-signed cert, не Developer ID, не
  нотаризован. Первый запуск свежеустановленной копии всё равно
  упрётся в Gatekeeper (выполни `xattr -cr` как описано в Установке). Между
  пересборками идентичность стабильна, так что Keychain ACL и
  TCC grants переживают.
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

Apache License 2.0. См. [`LICENSE`](LICENSE).
