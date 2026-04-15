# Whisper Local — план реализации

Локальное macOS-приложение для голосовой транскрибации в строке меню. Нажатие горячей клавиши → запись → второй хоткей → транскрибация → текст в буфер обмена и автоматически вставляется в активное окно.

---

## 1. Цели и UX-сценарий

**Основной флоу (happy path):**
1. Пользователь в любом приложении (Slack, Notes, браузер, IDE) ставит курсор в текстовое поле.
2. Нажимает глобальный хоткей (по умолчанию `Fn`, с фоллбэком на `⌥⌘+5`) → слышит короткий приятный старт-сигнал → в менюбаре иконка меняется на «запись», опционально появляется мини-индикатор (pill / waveform).
3. Говорит.
4. Повторно нажимает хоткей → стоп-сигнал → иконка уходит в состояние «обработка».
5. Аудио уходит в выбранный транскрайбер → возвращается текст.
6. Текст кладётся в `NSPasteboard` и автоматически эмулируется `⌘V` в активное приложение через `CGEventPost`.
7. Notification / мягкий чайм «готово». Иконка в менюбаре возвращается в покой.

**Дополнительные сценарии:**
- Отмена записи (Esc или клик по иконке).
- Повторная вставка последнего результата из истории.
- Просмотр последних N транскрибаций в поповере (опция «Show in panel»).
- Только копирование в буфер без автопейста (переключатель в настройках, как на скриншоте).

---

## 2. Технологический стек

| Слой | Выбор | Обоснование |
|---|---|---|
| Язык | **Swift 5.9+** | Нативный macOS, минимум рантайма, лучшая поддержка системных API (AppKit, AVFoundation, Accessibility). |
| UI | **AppKit `NSStatusItem` primary + SwiftUI внутри** | Для утилиты с non-activating overlay-панелями, точным контролем фокуса и долгоживущим состоянием AppKit предсказуемее, чем `MenuBarExtra`. SwiftUI живёт в hosted-view внутри поповера и в Settings scene. Никакого «MenuBarExtra с fallback» — одна модель владения. |
| Мин. версия | macOS 13 Ventura | Поддержка `MenuBarExtra`, современный SwiftUI. Опционально 14 Sonoma для упрощения. |
| Архитектура | MVVM + Services + Combine | Чистое разделение: UI, state, services (audio/hotkey/transcription/paste). |
| Хранение настроек | `UserDefaults` + **Keychain** для API-ключей | API-ключи никогда не в plist. |
| Запись звука | `AVAudioEngine` + `AVAudioFile` (WAV 16kHz mono) | Оптимальный формат для Whisper/GPT-4o-Transcribe, меньше трафика. |
| Глобальный хоткей | **Carbon `RegisterEventHotKey`** (дефолт `⌥⌘+5`) + опц. `CGEventTap` для Fn | Fn — **НЕ дефолт**. Это хардварное состояние с конфликтами (system Dictation, пользовательские переопределения). Fn доступен как экспериментальный opt-in через event tap на `NSEvent.EventTypeMask.flagsChanged`. |
| Автопейст | `NSPasteboard` + `CGEventPost` (синтез `⌘V`) | Требует Accessibility permission. |
| Звуки | `AudioServicesPlaySystemSound` с кастомными `.caf` | Низколатентно, не блокирует UI. |
| Транскрибация | **Плагины провайдеров** (см. §4) | Пользователь выбирает в настройках. |
| Упаковка | `.app` bundle → `.dmg` с drag-to-Applications | Стандарт macOS. Подпись + нотаризация — опционально для личного использования (ad-hoc sign). |

**Почему Swift, а не Python+rumps:** Python-приложения под macOS не дают нормального доступа к `CGEventTap`, сложно распространять как `.app`, хуже производительность иконки в менюбаре, проблемы с sandbox и нотаризацией. Swift — правильный выбор.

**Почему AppKit `NSStatusItem` primary, а не `MenuBarExtra`:** `MenuBarExtra` (macOS 13+) — удобный SwiftUI-сахар, но для утилиты с кастомными non-activating панелями, восстановлением фокуса, синтетическим пейстом и долгоживущим состоянием он течёт в краевых случаях. `NSStatusItem` даёт полный контроль над lifecycle, фокусом, popover-панелями и `NSPanel`-ами. SwiftUI подключается через `NSHostingView` внутри поповера и Settings scene.

---

## 3. Архитектура модулей

```
WhisperLocal.app/
├── App/
│   ├── WhisperLocalApp.swift         // @main, AppKit NSApplication lifecycle, Settings scene
│   └── AppDelegate.swift             // NSStatusItem owner, permissions bootstrap, launch-at-login
├── MenuBar/
│   ├── MenuBarController.swift       // NSStatusItem state machine (idle/recording/processing/error) — AppKit primary
│   ├── MenuBarIcon.swift             // SF Symbol + animation при записи
│   └── PopoverHost.swift             // NSPopover с NSHostingView(rootView: SwiftUI content)
├── Hotkey/
│   ├── HotkeyManager.swift           // фасад
│   ├── FnKeyMonitor.swift            // CGEventTap → detects Fn press/release
│   └── CarbonHotkey.swift            // RegisterEventHotKey для ⌥⌘+5 и пр.
├── Audio/
│   ├── AudioRecorder.swift           // AVAudioEngine, файл в tmp
│   ├── AudioLevelMeter.swift         // RMS level для waveform-индикатора
│   └── SoundPlayer.swift             // start/stop/done chimes
├── Transcription/
│   ├── TranscriptionService.swift    // протокол: transcribe(url, lang) async throws -> String
│   ├── Providers/
│   │   ├── OpenAISTTProvider.swift        // /v1/audio/transcriptions
│   │   ├── GroqSTTProvider.swift          // /v1/audio/transcriptions, whisper-large-v3-turbo
│   │   ├── LocalWhisperProvider.swift     // whisper.cpp через XPC / bundled binary
│   │   ├── OpenRouterAudioProvider.swift  // /v1/chat/completions с input_audio (gpt-4o-audio-preview и др.)
│   │   └── OpenAIAudioProvider.swift      // /v1/chat/completions с input_audio (прямой)
│   └── PostProcessor.swift                // опц. LLM-доводка через любого провайдера
├── Paste/
│   ├── PasteboardWriter.swift
│   └── PasteSimulator.swift          // CGEventPost ⌘V
├── Indicator/
│   ├── ClassicWaveformView.swift     // floating NSPanel с waveform
│   ├── MiniPillView.swift            // "mini (pill)" как на скриншоте
│   └── IndicatorController.swift     // переключение стилей
├── Settings/
│   ├── SettingsView.swift            // SwiftUI форма из скриншота
│   ├── PreferencesStore.swift        // @AppStorage + Keychain bridge
│   └── KeychainService.swift
├── Permissions/
│   ├── PermissionsCoordinator.swift  // Mic, Accessibility, Input Monitoring
│   └── OnboardingView.swift          // первый запуск
├── History/
│   └── TranscriptHistory.swift       // последние N записей, Core Data или SQLite
└── Resources/
    ├── Sounds/ (start.caf, stop.caf, done.caf)
    └── Assets.xcassets (иконки, SF Symbols)
```

---

## 4. Транскрибация — провайдеры

**Важное уточнение (пересмотрено после ревью):** OpenRouter **поддерживает** audio input на совместимых моделях через `/chat/completions` — в частности `openai/gpt-4o-audio-preview` принимает аудио для транскрибации/анализа. Первая версия плана утверждала обратное — это было неверно.

**Два класса провайдеров, оба доступны для транскрибации:**

### A. Dedicated STT API (`/audio/transcriptions`-совместимые)
Оптимальны, когда нужны STT-специфичные фичи: таймкоды, response_format, явный язык, segment-level output.
- **OpenAI** — `whisper-1`, `gpt-4o-transcribe`, `gpt-4o-mini-transcribe`. Как на скриншоте, эталон точности.
- **Groq** — `whisper-large-v3`, `whisper-large-v3-turbo`. В ~10× быстрее и дешевле, отличное качество.
- **Local whisper.cpp** — полностью офлайн. Модели (`base`, `small`, `medium`, `large-v3`) скачиваются по требованию; не бандлятся в `.app`.

### B. Chat Completions с audio input (OpenRouter и прямой OpenAI API)
Оптимальны, когда пользователь хочет выбрать любую модель из каталога OpenRouter одним ключом.
- **OpenRouter** (`openai/gpt-4o-audio-preview`, `google/gemini-2.0-flash`, и другие audio-capable модели) — один API-ключ открывает доступ к десяткам моделей. Аудио отправляется в сообщении как `input_audio` с base64 + формат.
- Плюсы: единый биллинг, быстрый онбординг, авто-расширение каталога.
- Минусы: не все модели возвращают clean-text транскрипт без лишних пояснений — нужна системная инструкция типа «return the transcript only, no commentary».

### Пост-обработка (опционально, отдельный шаг)
После получения сырого текста — опциональный LLM-cleanup через ту же OpenRouter или прямого провайдера:
- чистка филлеров (эм, ну, типа),
- пунктуация, капитализация,
- перевод,
- переформулирование в стиль (email / Slack-casual / техдок).
- Выключается отдельным тумблером — чтобы не замедлять основной флоу.

### UI настроек — два отдельных блока
- `Transcription provider` → выбор класса (Dedicated STT / OpenRouter Chat) → выбор модели → ключ.
- `Post-processing (optional)` → ключ (может совпадать с основным) + модель + пресет промпта.

### Абстракция в коде
Протокол `TranscriptionService` с реализациями:
```
OpenAISTTProvider       // /v1/audio/transcriptions
GroqSTTProvider         // /v1/audio/transcriptions
LocalWhisperProvider    // whisper.cpp
OpenRouterAudioProvider // /v1/chat/completions с audio input
OpenAIAudioProvider     // /v1/chat/completions с audio input (прямой)
```
Все приводятся к `func transcribe(url: URL, language: Language?, options: Options) async throws -> String`. Пользователь выбирает любой в настройках.

---

## 5. Горячая клавиша — дизайн

**Решение после ревью:** `Fn` НЕ дефолтный хоткей. Слишком хрупко: хардварное состояние, конфликты с системной Dictation/Emoji, нет публичного API чтобы программно ребайндить, поведение зависит от модели клавиатуры и пользовательских настроек. Fn остаётся как **экспериментальный opt-in** в настройках, с явным предупреждением.

### Дефолт: `⌥⌘+5` через Carbon `RegisterEventHotKey`
- Публичный, стабильный, работает без Input Monitoring permission.
- Toggle-логика: первое нажатие → start, второе → stop.
- Настраиваемый — пользователь может переназначить на любую комбинацию в Settings.

### Опциональный режим: Fn через `CGEventTap`
- Установить `CGEventTap` с маской `.flagsChanged`.
- В каллбэке читать `event.flags.contains(.maskSecondaryFn)`.
- Отслеживать переходы press↔release.
- Требует **Input Monitoring permission**.
- В онбординге при включении Fn-режима:
  - Инструкция «System Settings → Keyboard → Press 🌐 key to → **Do Nothing**» (с диплинком `x-apple.systempreferences:com.apple.preference.keyboard`).
  - Предупреждение: «Programmatic override недоступен — если вы не отключите системное действие Fn, обе функции сработают одновременно».
- API `CGEventTap` + `maskSecondaryFn` + `NSEvent.ModifierFlags.function` **подтверждены как актуальные публичные API** — используем без угрызений совести, но понимаем границы того, что они могут.

### Альтернативы в UI настроек
- Normal combo (default, `⌥⌘+5`)
- Custom combo — рекордер в настройках
- Fn key (experimental) — с чекбоксом подтверждения и предупреждением
- Push-to-talk vs toggle — отдельная опция

---

## 6. Поток данных (state machine)

```
idle ──hotkey──▶ requestingPermissions? ──▶ recording ──hotkey──▶ stopping ──▶ transcribing ──▶ postProcessing? ──▶ pasting ──▶ idle
                                               │                                                                        │
                                               └──esc/cancel──▶ cancelled ──────────────────────────────────────────────┘
                                                                      │
                                                                      └──error──▶ errorToast ──▶ idle
```

Каждый переход:
- обновляет иконку в менюбаре,
- опционально проигрывает звук,
- показывает/скрывает индикатор.

---

## 7. Разрешения (critical — без них приложение бесполезно)

| Permission | Зачем | Как запрашивается |
|---|---|---|
| **Microphone** | Запись аудио | `AVCaptureDevice.requestAccess(for: .audio)` при первой записи |
| **Accessibility** | `CGEventPost` для ⌘V автопейста | `AXIsProcessTrustedWithOptions` + диплинк в настройки |
| **Input Monitoring** | `CGEventTap` для Fn / глобальных хоткеев | Диплинк `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent` |
| (опц.) **Automation** | Если используем AppleScript для вставки | Не обязательно, если идём через CGEventPost |

Онбординг-окно при первом запуске прогоняет все три permission с чеклистом и кнопками «Open Settings».

---

## 8. Настройки (маппинг на скриншот)

Из скриншота видно точный набор полей — реплицируем 1:1 + расширяем:

**Существующие (из макета):**
- **API Key** → `sk-...` (но у нас будет раздельно: OpenAI key, OpenRouter key, Groq key — показываем только актуальный)
- **Model** → выпадающий список: `gpt-4o-transcribe (recommended)`, `gpt-4o-mini-transcribe`, `whisper-1`, + Groq модели, + локальные whisper.cpp
- **After transcription:**
  - ☑ Copy to clipboard (paste manually with ⌘V)
  - ☐ Show in panel
  - ☑ **Auto-paste to active app** (добавляем — пользователь явно просил)
- **Recording indicator Style:** Classic (waveform) / Mini (pill) / None (menubar only)
- **Hotkey:** дефолт `⌥⌘+5`, рекордер для кастомной комбинации, **отдельный чекбокс «Use Fn key (experimental — read warning)»** с раскрывающимся предупреждением

**Добавляем:**
- **Language** → auto-detect / English / Russian / Latvian / … (пользователь явно просил)
- **Output format** → plain text / markdown / with timestamps (пользователь явно просил «выбор выхода»)
- **Sounds** → тумблер + выбор из 3 пресетов чаймов
- **Post-processing** (отдельная секция):
  - Enable LLM cleanup
  - OpenRouter key
  - Model picker (список моделей из OpenRouter `/models` endpoint)
  - Prompt preset: Raw / Cleanup filler words / Email style / Slack casual / Custom…
- **History** → сохранять N последних транскрипций
- **Launch at login** (через `SMAppService` macOS 13+)

---

## 9. Индикаторы записи

1. **Menubar icon only** — `microphone.fill` → `waveform` с pulse-анимацией.
2. **Mini pill** — маленький floating `NSPanel` у нотча (как на скриншоте в поповере). Показывает таймер и RMS-уровень.
3. **Classic waveform** — панель побольше, настоящая визуализация через Metal/CoreGraphics.

Все варианты — `.nonactivatingPanel` + `.statusBar` level, не крадут фокус у активного окна (критично для автопейста!).

---

## 10. Звуковые сигналы

- `start.caf` — короткий восходящий арпеджио (~150 ms).
- `stop.caf` — мягкий нисходящий «клик» (~120 ms).
- `done.caf` — тёплый «ping» после успешной транскрибации.

Бандлятся в `Resources/Sounds/`. Воспроизводятся через `AudioServicesCreateSystemSoundID` — минимальная латентность, не перехватывают аудио-сессию записи.

Генерируем заранее в GarageBand / Logic или берём CC0 (freesound.org) — в плане учтено, что это нужно подготовить.

---

## 11. Автопейст — корректность важнее простоты

Синтетический `⌘V` через `CGEventPost` — рабочий, но **не детерминированный** подход. Плохо написанный пейст клобит пользовательский клипборд и промахивается по фокусу. Переписываем с защитами.

### Pre-conditions (проверяем ДО пейста)
1. **Frontmost-app check:** снапшот фронтмост-аппа взят в момент старта записи (NSWorkspace.frontmostApplication). Перед пейстом — проверяем, что фронтмост-апп тот же самый. Если фокус изменился → показываем нотификацию «Focus changed, text copied to clipboard» и НЕ пейстим.
2. **Не пейстим в самих себя:** если bundle identifier фронтмост-аппа — наш, абортируем автопейст (пользователь случайно вернулся в Settings).
3. **Secure text field guard:** `IsSecureEventInputEnabled()` → если TRUE, это secure input (пароль, sudo в Terminal, 1Password). **НИКОГДА** не пейстим автоматически, только копируем. Показываем явное уведомление «Secure input detected — pasted to clipboard only».
4. **Input source check:** опционально проверяем через AX, что у фронтмост-аппа есть focused UI element типа текстового поля.

### Pasteboard lifecycle
```
1. Snapshot предыдущего содержимого NSPasteboard.general (все types, не только string) + changeCount
2. Write text → NSPasteboard.general
3. Проверить pre-conditions (см. выше). Если любое не выполнено → notification + return.
4. Поставить pasteboard на owned mark через declareTypes(owner:self) — чтобы отслеживать, не перехватил ли кто
5. CGEventPost(⌘V keydown) → CGEventPost(⌘V keyup) через CGEventSource(.combinedSessionState)
6. Дожидаемся подтверждения: pollим changeCount с таймаутом 500 ms — это показатель, что пейст прошёл
7. Восстановление пред. pasteboard: ТОЛЬКО если пользователь явно включил опцию И changeCount НЕ менялся никем другим после нашего write. Если менялся — не трогаем, иначе сотрём свежие действия пользователя.
```

### Почему не восстанавливать pasteboard по умолчанию
Race condition: пользователь копирует что-то в другом окне между нашим write и restore → restore затирает его копию. Безопаснее **оставить нашу транскрипцию в буфере** (пользователь явно её туда положил). Restore — опциональная фича с явным warning.

### AX-insertion — НЕ generic fallback
`AXUIElementPerformAction` / `kAXValueAttribute` для прямой вставки в текстовое поле работает **нестабильно** поперёк AppKit/WebKit/Electron/Catalyst/custom editors. Используем как **per-app best-effort**:
- Нативные AppKit-приложения — AX set value на focused element может сработать.
- Electron, WebKit, Terminal — fallback на synthetic ⌘V.
- Ведём whitelist «AX-friendly» bundle identifiers, для остальных сразу synthetic paste.
- В плане M6 AX-режим НЕ включён — добавляем как опциональное улучшение позже.

### Secure Keyboard Input
Terminal и некоторые секьюрити-утилиты могут держать «Secure Keyboard Input» глобально — это блокирует перехват / доставку синтетических событий. Детектим через `IsSecureEventInputEnabled()` и честно сообщаем пользователю вместо тихого фейла.

### Activation policy
Приложение — `LSUIElement=true` (не регистрируется в Dock, не крадёт фокус). Settings scene открывается явным выбором из меню и сама обрабатывает `NSApp.setActivationPolicy(.regular)` только на время открытия окна, возвращая `.accessory` при закрытии.

---

## 12. Установочный файл

**План упаковки:**
1. Xcode build → `WhisperLocal.app`
2. `codesign --deep --force --sign -` (ad-hoc для личного использования) или Developer ID для раздачи
3. `create-dmg` CLI → `WhisperLocal-1.0.0.dmg` с фоном и стрелкой к папке `Applications`
4. Для раздачи: `xcrun notarytool submit` + `stapler staple`

Пользователю достаточно: скачать `.dmg` → перетащить в Applications → первый запуск → онбординг → разрешения → готово.

---

## 13. Этапы реализации (milestones)

**Честная оценка после ревью: MVP = 2–4 недели одного инженера, не 9 дней.** Хардкор не в UI, а в OS-интеграции: хоткеи, permissions, non-activating overlays, корректный синтетический пейст, restore-race-conditions, focus-races, абстракция провайдеров. Прошлая оценка предполагала, что каждый OS-нюанс сработает с первого раза — это не так.

| # | Milestone | Объём (чистого времени) | Проверяемый результат |
|---|---|---|---|
| M1 | Скелет AppKit + NSStatusItem | 1 день | Иконка в менюбаре, пустое меню, Settings scene открывается/закрывается без утечек фокуса |
| M2 | Запись аудио (AVAudioEngine) | 1.5 дня | Кнопка «Record» пишет WAV 16kHz mono в tmp, RMS-level, корректная реакция на смену input device / mute |
| M3 | Глобальный хоткей `⌥⌘+5` (Carbon) | 0.5 дня | Toggle start/stop, пользовательский рекордер в настройках |
| M4 | OpenAI STT + Keychain | 1 день | Реальный текст возвращается, ключ в Keychain, обработка ошибок сети |
| M5 | Pasteboard + автопейст с guard'ами | 2 дня | Focus check, secure-input guard, pasteboard snapshot/restore, тест на 5 разных apps (Notes, Slack, Chrome, Terminal, VS Code) |
| M6 | Звуковые сигналы | 0.5 дня | Чаймы на старт/стоп/готово, low-latency через AudioServicesPlaySystemSound |
| M7 | Permissions onboarding | 1.5 дня | Первый запуск ведёт через Mic + Accessibility + (опц.) Input Monitoring с диплинками и валидацией |
| M8 | Settings UI | 1.5 дня | Полная форма из скриншота, биндинги на Keychain/UserDefaults, рекордер хоткея |
| M9 | Индикаторы (pill + waveform) | 2 дня | Non-activating NSPanel, корректное поведение под Stage Manager / multi-display / Spaces |
| M10 | OpenRouter audio provider | 1 день | `/chat/completions` с input_audio, системный промпт для clean-text output |
| M11 | Groq + Local whisper.cpp | 1.5 дня | Выбор провайдера в настройках, download-on-demand для local моделей |
| M12 | LLM post-processing (опц.) | 0.5 дня | Тумблер + пресеты |
| M13 | История транскрипций | 1 день | Encrypted-at-rest хранение, последние 10 с кнопкой re-paste, опция «disable history» |
| M14 | Privacy & retention policy | 0.5 дня | Temp-file lifecycle, явные настройки retention, экран «Privacy & Data» в Settings |
| M15 | Fn-key experimental opt-in | 1 день | CGEventTap + Input Monitoring permission + warning dialog |
| M16 | Launch at login (SMAppService) | 0.25 дня | Автозапуск работает |
| M17 | DMG упаковка + ad-hoc sign | 1 день | Готовый `.dmg` устанавливается на чистую систему, нет Gatekeeper-блока |
| M18 | Edge-case hardening | 2 дня | Тест на focus-race, Stage Manager, несколько дисплеев, AirPods-switching, мьют/сброс input device, secure input в Terminal |

**Итого:** тонкий MVP (M1–M9 без Fn, без доп. провайдеров, без истории) ≈ **11 рабочих дней**. Полный MVP со всеми провайдерами, privacy и edge-cases ≈ **20 рабочих дней**. Не оптимистичный 9-дневный план — код физически напишется, но OS-интеграция отъест остаток бюджета.

---

## 14. Риски и correctness-issues

### Критичные для корректности (не косметика)

1. **Focus race: пейст в чужое окно.** Между стопом записи и пейстом проходит 1–5 сек (время транскрибации). Пользователь успеет переключить окно. **Mitigation:** снапшот frontmost-app в момент старта записи, проверка перед пейстом. Если не совпадает — notification «Focus changed, text copied to clipboard», без автопейста. См. §11.

2. **Пейст в собственное Settings-окно.** Пользователь открыл Settings → нажал хоткей → записал → наше Settings стало frontmost → пейст в наш же текстфилд. **Mitigation:** bundle ID check, абортируем если frontmost == self.

3. **Secure input (пароли, sudo, 1Password).** `IsSecureEventInputEnabled() == true` → **никогда** не пейстим автоматически. Только клипборд + явная нотификация.

4. **Pasteboard restore race.** Если мы «восстанавливаем» предыдущий буфер через 200 ms, а пользователь за это время скопировал что-то ещё — затираем его копию. **Mitigation:** restore — opt-in, и только если `changeCount` не менялся после нашего write.

5. **Secure Keyboard Input (Terminal).** Некоторые приложения включают global Secure Keyboard Input, что блокирует синтетические события. **Mitigation:** детектим и сообщаем пользователю.

6. **Focus change во время записи.** Пользователь переключил окно между start и stop — это нормально, запись продолжается, но frontmost на момент пейста может не совпасть с frontmost на момент старта. Вопрос UX: пейстить в текущее или в стартовое? **Решение:** пейстим в **стартовое**, если оно всё ещё активно; иначе абортируем с нотификацией.

7. **Stage Manager / multi-display / Spaces.** Non-activating `NSPanel` для индикатора должен корректно располагаться на активном экране, не вылезать за пределы, не залипать в пустом Space. **Mitigation:** пересчитываем screen frame по `NSScreen.main` на каждый show, используем `.canJoinAllSpaces` и `.stationary` collection behavior.

8. **Input device switching во время записи.** AirPods подключились/отключились, пользователь переткнул USB-микрофон, включил mute. `AVAudioEngine` получит interruption. **Mitigation:** observe `AVAudioEngine.configurationChange` и `AVCaptureDevice` notifications; при смене — корректно завершить запись или показать ошибку. **НЕ тащить паттерны `AVAudioSession` из iOS** — на macOS их нет, другой API.

9. **Mic contention.** Zoom/Teams на macOS не берут exclusive ownership микрофона, так что параллельная запись обычно работает. Но **реальная проблема** — input routing меняется, когда Zoom меняет device. Плюс приложения могут менять сэмплрейт/формат. **Mitigation:** не кэшируем AudioUnit конфигурацию между записями, reinit на каждый start.

10. **Стоимость ошибки AX fallback.** AX-insert работает нестабильно поперёк AppKit/WebKit/Electron. Не ставим её как generic fallback — только per-app best-effort whitelist. В MVP не включаем.

### Менее критичные

11. **whisper.cpp размер моделей** — `large-v3` ≈ 3 ГБ. Download-on-demand, не бандлим. Progress-indicator при скачивании.

12. **Стоимость `gpt-4o-transcribe`.** Заметно дороже `whisper-1`. В UI показать ориентир «≈ $0.006/min» рядом с моделью. Для OpenRouter — брать цену из `/models` endpoint.

13. **Латентность.** Цель ≤ 2 сек для 10-сек записи (Groq быстрее всех, GPT-4o-transcribe ~1–3 сек, whisper-1 ~3–5 сек, local whisper.cpp medium ~2–5 сек на M1). Показать реалистичные ожидания в настройках.

14. **Sandbox.** `CGEventTap` + `CGEventPost` по дизайну несовместимы с App Sandbox (не entitlement paper-cut, это design incompatibility). Приложение **non-sandboxed**, только прямая раздача `.dmg`, не Mac App Store. Для утилиты — ОК.

### Открытые вопросы для пользователя

- Нужен ли в MVP Local whisper.cpp, или начинаем только с OpenAI+OpenRouter+Groq? (Local добавляет ~1.5 дня и требует скачивания моделей.)
- Включать ли Fn-режим в первую публичную версию, или оставить как скрытый dev-toggle?
- Хотите ли историю транскрипций по умолчанию, или default = off с явным opt-in? (Рекомендую off.)

---

## 14a. Privacy & data handling

План «local app» не означает «без cloud». OpenAI/Groq/OpenRouter STT-провайдеры получают audio-файлы по сети. Это нужно сказать пользователю явно, не footnote'ом.

### Temp-file lifecycle
- Аудио пишется в `~/Library/Caches/WhisperLocal/recordings/` (не `/tmp` — более контролируемо).
- Имя файла: UUID, без связи с временем.
- **Удаление сразу после успешной транскрибации.**
- Если транскрибация упала — оставляем на 24 часа с ретраем, потом удаляем.
- Никаких crash-dumps с аудио.

### Транскрипты (история)
- **По умолчанию — история выключена.** Пользователь включает явно.
- Если включена: хранение в SQLite в `~/Library/Application Support/WhisperLocal/`, **encrypted at rest** через CryptoKit+SecItem (ключ в Keychain).
- UI «Clear history» с подтверждением.
- Retention-настройка: 1 день / 7 дней / 30 дней / навсегда.

### Cloud-провайдеры — явное раскрытие
- На экране первого запуска: «Transcription uses cloud providers you configure. Audio will be sent to OpenAI/Groq/OpenRouter for processing. Choose Local Whisper for fully offline operation.»
- Ссылки на privacy policies каждого провайдера.
- Для OpenAI: отметить, что API data retention — 30 дней по умолчанию, с опцией zero-retention для enterprise.

### Pasteboard — глобально читаемый ресурс
- Любое приложение на Mac может прочитать `NSPasteboard.general`.
- Менеджеры буфера (Paste, Alfred, Raycast clipboard history) **сохранят транскрипцию навсегда** в своей истории.
- В онбординге: явное упоминание — «Your transcript will be placed on the system clipboard. Clipboard manager apps may save it in their history.»

### Keychain
- Все API-ключи в Keychain с `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Не синхронизировать через iCloud Keychain (может быть нежелательно для API-ключей).

### Без аналитики / crash-reporting в MVP
- Никакого Sentry/Firebase/Plausible.
- Если понадобится — только opt-in в настройках, с чётким disclosure.

---

## 15. Что НЕ делаем в MVP

- Облачную синхронизацию истории.
- Multi-language UI (само приложение на английском).
- Mac App Store дистрибуцию.
- Streaming-транскрибацию в реальном времени (запись → отправка целиком по стопу — проще и надёжнее).
- Поддержку старых macOS (< 13).
- Интеграцию с Shortcuts.app (можно добавить позже одним AppIntent).

---

## 16. Первый коммит — что делаем сразу после утверждения плана

1. `xcodegen` / руками `WhisperLocal.xcodeproj` с таргетом macOS 13+, `LSUIElement=true`
2. AppKit `NSApplicationDelegate` + `NSStatusItem` с иконкой-микрофоном, пустое меню
3. Settings scene (SwiftUI внутри AppKit host), пока с одним полем «OpenAI API key»
4. `AudioRecorder` (AVAudioEngine → WAV 16kHz mono в `~/Library/Caches/WhisperLocal/`)
5. Кнопка «Start/Stop recording» в меню (хоткей — позже)
6. `OpenAISTTProvider` — ключ временно из UserDefaults (Keychain — позже), вызов `/v1/audio/transcriptions`
7. Текст в `NSPasteboard` БЕЗ автопейста — чисто копирование на этом этапе
8. Проверяем end-to-end: клик → запись → стоп → текст в буфере обмена

**Это даёт рабочий прототип за ~2 дня**, от которого дальше наращиваем: хоткей, автопейст с guard'ами, permissions onboarding, индикаторы, провайдеры, упаковка.

Критично: **не начинаем с автопейста и Fn-key** — это главные источники проблем, они должны быть ПОСЛЕ того как весь остальной флоу работает.

---

## 17. Что изменилось по сравнению с первой редакцией плана

Этот план был пересмотрен после ревью codex. Главные правки:

1. **OpenRouter → полноправный STT-провайдер.** Первая редакция ошибочно утверждала, что OpenRouter не поддерживает audio input. По факту (на 2026-04-14) поддерживает — `openai/gpt-4o-audio-preview` и другие audio-capable модели через `/chat/completions` принимают `input_audio`. Архитектура теперь имеет два класса провайдеров: dedicated STT API и Chat Completions с audio input.
2. **Fn-key → НЕ дефолт.** Дефолт `⌥⌘+5` через Carbon `RegisterEventHotKey`. Fn остаётся как экспериментальный opt-in с предупреждением.
3. **AppKit `NSStatusItem` → primary shell.** Вместо `MenuBarExtra + fallback`. SwiftUI только внутри hosted views и Settings scene.
4. **Автопейст → с correctness-guards.** Focus check, secure-input guard, pasteboard-restore только при non-modified changeCount, AX не позиционируется как generic fallback.
5. **Оценка 9 дней → 11–20 дней.** Хардкор в OS-интеграции, а не в UI. Тонкий MVP без Fn/истории/edge-cases — 11 дней; полный — 20.
6. **Privacy — отдельная секция.** Retention policy, encrypted-at-rest история (off по умолчанию), temp-file lifecycle, явное раскрытие cloud-провайдеров, pasteboard как глобально читаемый ресурс.
7. **Новые correctness-риски.** Focus race, пейст в собственное Settings-окно, Stage Manager/multi-display, input device switching (не копировать iOS `AVAudioSession` паттерны), Secure Keyboard Input в Terminal.
