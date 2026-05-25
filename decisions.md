# WhisperHot — Журнал архитектурных решений (ADR Log)

> Документ фиксирует **почему** в проекте сделан тот или иной выбор. «Что» описано в `ARCHITECTURE.md`, «как использовать» — в `README.md` и `CLAUDE.md`. Здесь — мотивация.
>
> Формат записи: **Контекст → Решение → Обоснование → Последствия → Альтернативы**.
>
> Версия приложения на момент ревизии: **0.7.2**.
>
> Автор: Aleksei Supilin. Лицензия: Apache 2.0.

---

## ADR-001 — AppKit shell + SwiftUI content, не чистый SwiftUI

**Контекст.** macOS voice-to-text приложение, которое записывает голос, транскрибирует и вставляет текст в активное приложение. Изначально оно было menu-bar-only; после 0.7.0 нужен полноценный Dock/main-window shell, но с тем же точным контролем записи, фокуса, status item и floating indicator.

**Решение.** AppKit (`NSApplicationDelegate`, `NSStatusItem`, `NSPanel`, `NSWindow`) для оболочки; SwiftUI внутри `NSHostingView` для Main Window, Settings, Setup, History и индикаторов записи.

**Обоснование.**
- Recording indicator — non-activating `NSPanel` с `collectionBehavior` (.canJoinAllSpaces, .stationary, .fullScreenAuxiliary). MenuBarExtra это не даёт.
- Auto-paste требует ручного focus handoff: перед стартом записи из Dashboard главное окно прячется, затем активируется сохранённое target-приложение.
- Main Window, Settings и Setup должны контролировать `previousApp`, чтобы запись и auto-paste не вставляли текст обратно в WhisperHot.

**Последствия.** Два мира (AppKit + SwiftUI) усложняют lifecycle. Компенсируется тем, что SwiftUI живёт только внутри hosting views, а AppKit владеет окнами, status item и focus handoff.

**Альтернативы.** SwiftUI `MenuBarExtra` — отвергнут из-за отсутствия контроля над окнами и focus management.

---

## ADR-002 — Swift 5.9 / SwiftPM, zero external dependencies

**Контекст.** Персональный проект, замена SuperWhisper. Минимальная сложность сборки.

**Решение.** SwiftPM без внешних зависимостей. Все фреймворки — системные Apple (AppKit, SwiftUI, AVFoundation, CryptoKit, Security, Carbon).

**Обоснование.**
- Нет dependency hell. `swift build` работает сразу.
- Все API стабильны (Apple frameworks).
- Проект достаточно мал (~7550 LOC) чтобы не нуждаться в сторонних библиотеках.

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

## ADR-013 — Silent fallback на auth errors — opt-in, не default. Fix-release после broken-релиза — новый minor/patch, не реюз тега

**Контекст.** В 0.6.3 расширили `FallbackTranscriptionService`: при `.missingAPIKey`, HTTP 401/403, 5xx, 408/429, timeouts — автомаршрут на локальный whisper вместо бросания ошибки. Релиз был отозван после жалобы «перестало распознавать речь». Post-mortem показал: реальная причина — провайдер вернул 403 (ключ отклонён), и без расширенного fallback пользователь тоже получал бы тишину. Отдельно: при откате 0.6.3 оказалось, что `UpdateChecker.compareVersions` в `LocalSetup/UpdateChecker.swift` проверяет только `current < latest` — реюз того же номера 0.6.3 не докатился бы до пользователей, стоящих на сломанной 0.6.3. Пришлось бампить до 0.6.4.

**Решение.**
1. **Silent fallback на auth/HTTP ошибки (401/403/5xx) — НЕ включать по умолчанию.** Если когда-нибудь вернём, то как opt-in флаг в Preferences + явный баннер в статус-меню («⚠️ API-ключ не принят — используется локальный whisper»). Без баннера пользователь не понимает, почему транскрипт другого качества или на другом языке — что хуже, чем честная ошибка.
2. **Fix-release после отозванной версии — строго `+1` по semver.** Реюз того же тега оставляет пользователей сломанной версии без обновления из-за `compareVersions` семантики (`orderedAscending` only). Отозвали 0.6.3 → следующая 0.6.4. Если позже захочется переиспользовать номер 0.6.3, тег и release можно создать, но **latest**-релиз обязан быть `> max(installed_broken)`.

**Обоснование.**
- Первый пункт: пользователь не должен строить ментальную модель «работает = ok» на молчании. STT-ошибки — пограничная зона: стоимость «ошибка на ровном месте» высока, но стоимость «тихо подменили провайдер» — выше, потому что ломает доверие к результату.
- Второй пункт: UpdateChecker нарочно строго `<`, чтобы не откатывать пользователей вниз при релизах discontinued номеров. Следствие — fix-after-broken требует бампа.

**Последствия.**
- `FallbackTranscriptionService` (текущая версия) fallback'ится только на реальные offline-ошибки (`.notConnectedToInternet`, `.networkConnectionLost`) — как в 0.6.2. При 403 пользователь получает явную ошибку и знает, что делать.
- CHANGELOG 0.6.4 содержит объяснение отзыва 0.6.3 — публичная история отката.

**Альтернативы.**
- *Fallback с баннером (было в 0.6.3).* Отвергнуто без opt-in — слишком агрессивно для default.
- *UpdateChecker с `<=` для force-upgrade.* Создаёт петлю обновлений при неудачных релизах. Отвергнуто.
- *Реюз тега 0.6.3 с force-push.* Пользователи сломанной версии не узнали бы. Отвергнуто.

**Supersedes** частично ADR-006 (FallbackTranscriptionService): область срабатывания явно ограничена offline-ошибками, не auth/HTTP.

---

## ADR-014 — Timeout fallback только opt-in: slow cloud → local whisper по таймауту

**Контекст.** ADR-013 вернул строгую политику fallback: auth/HTTP/server ошибки не должны тихо подменять провайдера. Но есть другой UX-кейс: пользователь с рабочим API-ключом сидит на плохой сети, cloud STT висит долго (10+ секунд), а локальный whisper.cpp уже настроен. Это не auth-error и не server-error — это latency problem, и пользователю выгоднее получить чуть менее точный, но быстрый результат.

**Решение.** Добавлен opt-in флаг `Preferences.autoOfflineOnTimeout` (default `false`) и параметр `autoOfflineTimeoutSeconds` (default 10). Когда флаг включён И local whisper.cpp доступен, `FallbackTranscriptionService` race-ит primary против таймера через `withThrowingTaskGroup`. Local fallback запускается **последовательно**, только после того как race резолвится с `.timeout` или `.primaryFailure(offline)`:
- если primary успел до timeout — возвращается primary, local subprocess вообще не запускается;
- если timeout наступил первым — primary URLSession отменяется, СТАРТУЕТ local whisper, его результат возвращается с `usedOfflineFallback = true`;
- если primary упал с offline-ошибкой до timeout — поведение как до ADR-014;
- если local fallback не настроен — флаг игнорируется, ждём primary до конца.

Тоггл живёт в menu bar меню рядом с Provider submenu, чтобы пользователь мог быстро включить/выключить при смене сети.

**Обоснование.**
- Это осознанный latency fallback, а не silent masking auth/HTTP failures — пользователь сам включает поведение и понимает возможную смену качества/модели.
- `usedOfflineFallback = true` сохраняет существующий контракт: UI показывает баннер, post-processing пропускается.
- 10 секунд по умолчанию — порог, при котором cloud-провайдер с большой вероятностью реально завис, а не просто медленный.
- HTTP 401/403/5xx по-прежнему НЕ fallback'ятся: при non-offline primary-ошибке бросаем явно — ADR-013 остаётся валиден.
- **Последовательный, а не параллельный fallback.** Первая редакция запускала local whisper параллельно с primary. Codex review поймал баг: `LocalWhisperProvider` оборачивает `Process` в continuation, который НЕ реагирует на `Task.cancel()`. Поэтому при быстром cloud-успехе `withThrowingTaskGroup` всё равно ждал бы полного завершения локального subprocess'а перед возвратом результата. Архитектурный фикс — не запускать local до решения race'а.

**Последствия.**
- Fast path (cloud<10s): нулевой overhead, local whisper не стартует.
- Slow path (cloud>10s): user ждёт 10s + время local whisper. Принято.
- Cancellation primary-задачи кооперативная: `URLSession.dataTask` отменяется по `Task.cancel()`. Subprocess local fallback не запускается до race-резолва, поэтому проблемы не возникает.
- Под Swift 6 strict concurrency enum `RaceEvent` с `Error` cases может потребовать boxing. На 5.9 mode компилируется без warnings.

**Альтернативы.**
- *Treat `.timedOut` URLError as offline by default.* Отвергнуто: slow provider ≠ offline для всех пользователей.
- *NWPathMonitor-only fallback.* Не решает captive portal / packet loss / slow upload — только полное отсутствие сети.
- *Последовательный retry после timeout.* Хуже UX: пользователь ждёт timeout, потом ещё полный local whisper transcription.

**Tradeoff с ADR-013 (известный, документированный).** Когда timer срабатывает раньше, чем primary успел вернуть HTTP-ошибку (401/403/5xx), эта ошибка маскируется local-результатом. Codex review поймал это как нарушение ADR-013. Принято осознанно: пользователь явно включил тоггл «switch to local if slow», его mental model — "I don't care WHY cloud is slow, give me local". Banner `usedOfflineFallback` показывает, что переключение произошло — это visible сигнал, что cloud-результат не получен. На практике auth-ошибки возвращаются быстро (1-2s) и редко доживают до timeout. Полный фикс требовал бы либо cancellation-aware `LocalWhisperProvider` (отдельная задача), либо grace-period после timeout — оба расширяют scope. Решение: документировать как opt-in tradeoff, не блокировать релиз.

**Гард для local-primary.** Если пользователь выбрал `provider == .localWhisper`, тоггл игнорируется — иначе timer на медленной локальной транскрипции запустит дубликат той же local-задачи. Гард в `TranscriptionCoordinator.fromPreferences`: `timeoutRaceEligible = provider != .localWhisper && Preferences.autoOfflineOnTimeout`.

**Не Supersedes ADR-013.** ADR-013 запрещает silent fallback на auth/HTTP по умолчанию. ADR-014 разрешает opt-in fallback на latency, с явным acknowledgement что timeout-окно может частично перекрыть auth/HTTP-окно. Разные классы ошибок, разные политики, явный пользовательский opt-in.

---

## ADR-015 — Sleep/wake recovery: task ownership, ephemeral URLSession, per-session audio primitives

**Контекст.** Пользователь отрепортил «приложение виснет после возврата Mac'а из sleep, помогает только перезапуск». Не всегда. Конфигурация — cloud STT, Auto-offline OFF, cloud post-processing. Grep по коду подтвердил: до v0.6.9 НИ ОДНОГО observer'а на `NSWorkspace.willSleepNotification` / `didWakeNotification` нигде. Cross-консультация с Codex выявила три каскадных дефекта:

1. **`Task.detached` для транскрипции запускался без сохранения handle.** Никто не мог отменить stranded request. И stale Task мог дойти до `finishTranscription` уже после новой записи, обнулив state посреди работы.
2. **`URLSession.shared` с дефолтным `timeoutIntervalForResource = 7 days`.** Request, у которого ядро снесло TCP-сокет во время сна, мог жить неделю без surfacing ошибки.
3. **`AudioRecorder.stopRecording()` ждал `tapGroup.wait()` и `writerQueue.sync {}` на main thread.** Если callback или write-блок зависли во время suspend, main thread замораживался намертво.

**Решение.** Закрыть все три дефекта пятью атомарными коммитами в строгом порядке риска (наименее рискованное — первым). Sleep/wake становится first-class lifecycle событием с дедицированными observer'ами в `MenuBarController`.

1. **Step 1 — instrumentation.** Phase markers в `TranscriptionCoordinator.run` (`stt-begin/end/failed`, `pp-begin/end (ok|failed)`), `didSet` log на `RecorderState`, log-only sleep/wake observer'ы. Format-string injection guard для error.localizedDescription через `"%@"`.
2. **Step 2 — task ownership + epoch guard.** `transcriptionTask: Task<Void, Never>?` хранит handle. `transcriptionEpoch: UInt64` инкремент на `kickOffTranscription`; запускающийся Task захватывает свой epoch, при возврате `deliverTranscriptionResult(outcome:epoch:)` сравнивает с текущим — mismatch ⇒ дроп до `finishTranscription`.
3. **Step 3 — sleep/wake actions.** `handleWorkspaceWillSleep` для `.transcribing` отменяет task + бампает epoch + обнуляет UI bookkeeping (WAV оставляется на диске, retention sweep управляет). `handleWorkspaceDidWake` делает `syncHotkeyBindings()` против stale Carbon `EventHotKeyRef`, с guard на `isHotkeyRecorderArmed` чтобы не ломать Settings → Hotkey recorder.
4. **Step 4 — ephemeral URLSession.** Новый `Sources/WhisperHot/Networking/HTTPClient.swift` экспортит один shared `URLSession`: `URLSessionConfiguration.ephemeral`, `waitsForConnectivity = false`, `timeoutIntervalForRequest = 60`, **`timeoutIntervalForResource = 180`**. Все три cloud провайдера (`OpenAICompatibleSTTProvider`, `OpenRouterAudioProvider`, `LLMPostProcessor`) используют как default. DI preserved.
5. **Step 5 — `AudioRecorder.resetAfterWake()` + per-session `tapGroup`/`writerQueue`/`id`.** `ActiveSession` теперь владеет своими DispatchGroup и DispatchQueue (label `*.writer.<id>`); shared instance-level primitives удалены. Tap closure захватывает session **strongly** — stale callback не дотянется до WAV новой записи. `processTapBuffer(buffer:session:)` гейтит ВСЁ (RMS update + write) на `isLive = sessionLock.withLock { $0?.id == session.id }`. `resetAfterWake()` — best-effort non-blocking teardown: removes tap, stops engine, clears slot, сбрасывает `isRecording`. **Никогда не ждёт** `tapGroup` / `writerQueue`. Вызывается на `willSleep` для `.recording` и defensive на `didWake` для dark-wake / hibernate path.

**Обоснование.**

- **Atomic commits в порядке риска.** `/codex consult` явно рекомендовал не делать «shotgun fix», а разбить на 5 шагов так, чтобы audio reset (самый рискованный, без UI/state-machine тестов) был последним. Каждый шаг прошёл `codex review` отдельно — Codex поймал 7 P1/P2 в трёх проходах Step 5: stale tap → successor WAV; controller state desync after dark-wake; shared `tapGroup`/`writerQueue` poisoned by wedged callback; late tap writes after stop drain.
- **Per-session primitives — корневой фикс audio teardown deadlock.** Shared `tapGroup`/`writerQueue` означали что заклинивший callback из abandoned session отравлял `wait()` следующего `stopRecording()` навсегда. С per-session DispatchGroup новый `stopRecording` дренит ТОЛЬКО свою группу, которая чиста независимо от того, что случилось со старой.
- **Strong session capture в tap closure — корневой фикс race в processTapBuffer.** Альтернатива через `[weak self]` с lookup в `sessionLock` создавала окно где stale callback мог прочитать НОВУЮ session и записать buffer старой записи в новый WAV. Strong capture гарантирует callback видит свою session.
- **`isLive` gate перед write — защита WAV от late tap.** Callback queued AVAudioEngine'ом ДО `removeTap` может фильнуть после `stopRecording` уже отдал WAV транскрибатору. Без guard'а write мог бы корраптить файл mid-read.
- **`timeoutIntervalForResource = 180s` — safety cap, не replacement.** Per-request `URLRequest.timeoutInterval` остаются (60s OpenAI, 120s OpenRouter, 60s LLM). Session-level cap — defence-in-depth: если per-request не сработал (URL-сессия залипла на dead socket post-wake), хотя бы 3 минуты будет потолком вместо 7 дней.
- **WAV не удаляется на sleep cancellation.** Match-ит `.failure` path `finishTranscription`. Пользователь с `.untilQuit` / `.oneHour` / `.forever` не теряет единственную копию аудио из-за прерывания сном.

**Последствия.**

- Sleep/wake более не теряет state приложения. UI после wake идёт через `idle` baseline.
- Cloud STT / LLM cleanup залипают максимум на 180 секунд вместо `~∞`.
- AudioRecorder теперь имеет публичный API `resetAfterWake()` — отдельный от `stopRecording()` контракт. `stopRecording` остаётся для clean teardown с гарантированным flush WAV header'а; `resetAfterWake` — для recovery где flush не critical, и main thread нельзя блокировать.
- `Process`-обёртки в `LocalWhisperProvider` / `LocalLLMProcessor` НЕ реагируют на `Task.cancel()` (continuation без cancellation handler). Subprocess продолжит работать после willSleep cancellation. Заметно только при выборе Local Whisper / Local LLM (cloud-only пользователей не касается). Tracked для отдельного фикса.
- Нет UI / state-machine тестов на `MenuBarController`. Sleep/wake handler'ы протестированы в release build manual smoke pass'ом, не automated tests. Project status.md F006 фиксирует gap.

**Альтернативы.**

- *Sample-driven fix.* Подождать `sample WhisperHot 10` от пользователя при следующем freeze, сделать минимальный фикс под конкретный стек. Codex рекомендовал НЕ ждать sample: архитектурные дефекты (no task ownership, no sleep/wake handling, shared primitives) — реальные баги независимо от того, какой именно стреляет. Sample всё равно стоит собрать как verification.
- *Cancellation handler в `LocalWhisperProvider` / `LocalLLMProcessor`.* `withCheckedThrowingContinuation { ... }` → `withTaskCancellationHandler`, который SIGTERM'ит subprocess. Out-of-scope для этого релиза (большой переработки subprocess lifecycle), но логичный next step.
- *Полный `engine.reset()` на didWake.* AVFoundation предлагает `engine.reset()`. Не используем — он может сам блокироваться на CoreAudio teardown в zombie-state. Наш `resetAfterWake()` обходится `removeTap + stop + clear slot` без `reset()`.

---

## ADR-016 — Полноценный macOS shell сейчас, Windows как отдельный платформенный порт

**Контекст.** Пользователь явно зафиксировал два направления: перестать быть приложением, которое "живёт в верхнем navbar", и в будущем поддержать Windows. Текущий код глубоко завязан на AppKit, AVAudioEngine, Keychain, TCC/Accessibility, Carbon hotkeys и macOS clipboard/paste APIs.

**Решение.** В 0.7.0 доводим native macOS shell: regular Dock app, главное окно, Dashboard, embedded Settings, History и Setup, при этом menu bar остаётся быстрым контроллером записи. Windows не пытаемся "включить" в SwiftPM; фиксируем отдельную дорожную карту в `docs/windows-support-plan.md` через platform adapters и spike, предпочтительно Tauri v2 + Rust core или Windows-first WinUI 3/C#.

**Обоснование.**
- Пользовательская боль сейчас на macOS UX: приложение не должно выглядеть как набор menu bar пунктов.
- Прямой порт Swift/AppKit на Windows невозможен практически: отсутствуют ключевые системные API.
- Platform adapters позволяют сохранить продуктовый pipeline и не ломать рабочую macOS-версию большим rewrite до проверки Windows MVP.

**Последствия.**
- macOS остаётся shipped-платформой текущего релиза.
- Windows support — принятое требование, но не заявленная фича 0.7.0.
- Новая архитектурная граница для будущих работ: бизнес-логика не должна напрямую зависеть от clipboard, hotkey, audio capture, active app context и secret storage конкретной ОС.

**Альтернативы.**
- *Оставить menu-bar-only и сразу делать Windows.* Отвергнуто: пользователь явно поставил macOS shell как ближайший приоритет.
- *Переписать всё в cross-platform shell немедленно.* Отвергнуто: слишком большой риск для уже работающего macOS workflow.
- *Swift on Windows.* Отвергнуто: проблема не в языке, а в отсутствующих AppKit/AVFoundation/Keychain/TCC API.

---

## ADR-017 — Keychain ACL repair + no secret polling in main window

**Контекст.** После установки `0.7.0` пользователь подтвердил, что GitHub
DMG запускается, но macOS снова просит пароль к login keychain и по два раза
требует `Разрешить всегда` после каждой новой сборки. Подпись bundle
проверена: designated requirement у `/Applications/WhisperHot.app` и
локального build output совпадает и завязан на
`identifier "com.aleksejsupilin.WhisperHot" and certificate leaf =
H"3e456ffaf9ca555c650522806ffb010acc8c528f"`. Значит проблема не в
текущей подписи, а в старых Keychain item ACL и частоте чтения secrets.

**Решение.** В `0.7.1`:

1. Production Keychain items (`service == com.aleksejsupilin.WhisperHot`)
   создаются и обновляются с явным `kSecAttrAccess`, сгенерированным для
   текущего приложения.
2. После успешного чтения старого production item WhisperHot делает
   best-effort ACL repair через `SecItemUpdate(kSecAttrAccess)`.
3. Тестовые service-id не получают ACL override, чтобы XCTest не зависал на
   системных Keychain prompts.
4. `MainWindowModel.refresh` больше не читает API key на 0.75s UI timer.
   Provider readiness перечитывает Keychain только на `onAppear`, при
   `UserDefaults.didChangeNotification` и после save/delete ключа.

**Обоснование.**
- Старые items могли быть созданы ad-hoc сборками или до стабилизации ACL;
  просто стабильной подписи недостаточно, если item уже доверяет старому
  requirement.
- Новое главное окно сделало проблему заметнее, потому что Setup readiness
  polling регулярно вызывал `SecItemCopyMatching`.
- Repair после успешного чтения сохраняет пользовательские ключи и требует
  максимум один финальный `Разрешить всегда` для старого item.

**Последствия.**
- На первом запуске `0.7.1` macOS может ещё раз спросить доступ к старым
  keys; после этого ACL должен обновиться и следующие сборки с тем же
  `whisper-hot-local` certificate не должны повторять prompt.
- Если repair не сработает, чтение всё равно возвращает данные: ACL migration
  best-effort и не ломает транскрипцию.
- Используется deprecated Keychain ACL API (`SecAccessCreate`) через dynamic
  lookup, потому что modern Keychain APIs не дают эквивалентной миграции ACL
  для существующих generic-password items без смены всей storage-модели.

**Альтернативы.**
- *Удалить и пересоздать все Keychain items.* Отвергнуто: пользователь
  потеряет API keys.
- *Оставить только стабильную подпись.* Недостаточно для items со старым ACL.
- *Перейти на другой secret storage.* Слишком большой scope для patch-релиза.

**Superseded by ADR-018.** На живых user items `kSecAttrAccess` repair мог
спровоцировать повторяющийся Keychain prompt-loop. Решение откатили в 0.7.2.

---

## ADR-018 — Hotfix: не читать Keychain на launch и откатить ACL repair

**Контекст.** После установки `0.7.1` пользователь сообщил, что приложение
постоянно спрашивает пароль от login keychain: после ввода prompt появляется
снова, уже 10+ раз. Процесс `WhisperHot` был остановлен, prompt-loop прекратился.
Это подтвердило, что 0.7.1 ACL-repair path сам стал триггером повторных
Keychain prompts.

**Решение.** В `0.7.2` полностью убрать risky ACL repair:

1. Удалить dynamic lookup `SecAccessCreate`.
2. Не задавать `kSecAttrAccess` при `SecItemAdd` / `SecItemUpdate`.
3. Не выполнять `SecItemUpdate(kSecAttrAccess)` после чтения.
4. Главное окно не читает API key при init, `onAppear`,
   `UserDefaults.didChangeNotification`, `WhisperHot.keychainDidChange` или
   0.75s timer. Cloud provider readiness показывается как deferred check.
5. Keychain остаётся на явных путях: Providers/Settings и transcription
   pipeline, где secret реально нужен.

**Обоснование.**
- Для emergency hotfix главный критерий — приложение должно открываться без
  prompt-loop.
- Старые ACL можно чинить только отдельным, явно запущенным maintenance flow,
  а не автоматической миграцией на launch/read.
- Deferred readiness лучше временно менее точного Setup, чем блокирующий
  системный prompt-loop.

**Последствия.**
- `0.7.2` supersedes `0.7.1`; `0.7.1` нельзя считать стабильной версией.
- Setup больше не гарантирует, что cloud API key существует, пока пользователь
  явно не откроет Providers или не начнёт transcription.
- Если старый Keychain item всё ещё имеет проблемный ACL, prompt может
  появиться при реальной транскрипции или открытии Providers. Это лучше, чем
  prompt-loop на старте, но требует отдельного ручного repair/reset сценария.

**Альтернативы.**
- *Продолжать ACL repair, но добавить once-per-run guard.* Отвергнуто:
  системный prompt уже показал, что сам repair unsafe.
- *Удалить старые items автоматически.* Отвергнуто: потеря API keys без явного
  согласия.
- *Оставить 0.7.1 latest и дать инструкцию пользователю удалить Keychain
  items.* Отвергнуто: latest должен быть безопасным по запуску.

---

## Про будущее (pending / не принято)

- **Windows-порт.** Требование принято, план в `docs/windows-support-plan.md`. Не shipped в 0.7.2.
- **Streaming транскрипция.** Plan в `docs/streaming-plan.md`. Deepgram/AssemblyAI ~$8/мес. Отложено — batch с Groq (0.5 сек, $0.90/мес) достаточен.
- **App Sandbox.** Несовместим с `Process` для brew/whisper/llama. Не активирован.
- **Apple Developer ID + нотаризация.** Убрал бы проблему с Gatekeeper ($99/год). Не приоритет для personal build.
- **Autoupdate (Sparkle).** Проверка обновлений есть, автоустановка — нет.
- **Дальнейший split MenuBarController.** ~840 строк — всё ещё много. Можно выделить MenuBuilder, RecordingStateMachine, HotkeyTransport. План в `TECH_DEBT_AUDIT.md` F006.
- **Раскол SettingsView.** 1007 строк, hottest churn-файл. План — 6 tab-файлов (`SettingsRecordingTab`, `SettingsProvidersTab`, etc.) в `TECH_DEBT_AUDIT.md` F005.
- **Backfill major test suites.** Providers (URLProtocol mock), AudioRecorder lifecycle, PasteService guards, TranscriptionCoordinator pipeline. Покрытие на сейчас: 54 теста, ContextRouter/FallbackTranscriptionService/WordReplacement/Keychain/HistoryStore зелёные. План в `TECH_DEBT_AUDIT.md` F001.

---

## Как обновлять этот файл

1. Любое **решение**, которое меняет стек, слой, границу или инфраструктуру, — новый ADR-N.
2. Не переписывай старые ADR. Если решение отменяется — добавь новый ADR со ссылкой `Supersedes ADR-N`.
3. Не описывай реализации (для этого `ARCHITECTURE.md`). Описывай **почему**.
4. Формат — **Контекст → Решение → Обоснование → Последствия → Альтернативы**.
5. Если целевая архитектура расходится с реализацией — укажи drift явно.
