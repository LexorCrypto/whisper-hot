# Продолжение STATUS — WhisperHot v0.6.9 hang-investigation release

Дата: 2026-05-09
Версия после сессии: **0.6.9** (PATCH bump, 5 атомарных коммитов)
Ветка: `main` (5 коммитов pushed на origin)
DMG/GitHub release: пока НЕ собран — следующий шаг.

---

## Что сделано в этой сессии

### Расследование

Пользователь отрепортил «приложение виснет после возврата Mac'а из sleep,
помогает только перезапуск», атрибутировал v0.6.6+. Скриншот меню
подтвердил: `Auto-switch to Offline when slow` = OFF.

Diff `v0.6.5..v0.6.6` — крошечный, единственное логическое изменение
(ADR-014 race code) при toggle OFF мёртвый. Атрибуция к v0.6.6 — слабая;
скорее timing совпадения. Реальный root cause — три pre-existing
архитектурных дефекта, выявленные двумя `/codex consult` в hybrid-режиме.

### Реализация (5 commits, codex review каждого)

| Commit | Step | Файлы | Что |
|--------|------|-------|------|
| `ef5ad33` | 1/5 | MenuBarController, TranscriptionCoordinator | Instrumentation: state didSet log, Task lifecycle markers, sleep/wake observers (log-only), pipeline phase markers. Codex: P2 format-string injection — fixed (`%@` для error). |
| `459aeaa` | 2/5 | MenuBarController | `transcriptionTask` ownership + `transcriptionEpoch` guard + `deliverTranscriptionResult(outcome:epoch:)`. Codex: clean. |
| `19744b5` | 3/5 | MenuBarController | willSleep отменяет Task для `.transcribing`, didWake re-arm hotkey с guard на `isHotkeyRecorderArmed`. Codex: P2 retention bypass — fixed (WAV не удаляется); P3 hotkey-armed — fixed. |
| `1f9d287` | 4/5 | Networking/HTTPClient.swift (новый), 3 провайдера | Ephemeral URLSession: `waitsForConnectivity=false`, `timeoutIntervalForResource=180s`. Codex: clean. |
| `67a3485` | 5/5 | AudioRecorder, MenuBarController | `resetAfterWake()` non-blocking + per-session `tapGroup`/`writerQueue`/`id`. Tap closure захватывает session strongly. `isLive` guard перед write. Codex (3 прохода): P1 stale tap → new WAV; P1 shared primitives poisoned; P2 controller state desync after dark-wake; P2 late tap writes after stop — все fixed. |

### Метрики

- Build: green каждый шаг, 0 warnings, release config.
- Tests: 54/54 green каждый шаг.
- Codex review: каждый diff отдельно, все findings зарезолвены до коммита.
- Code: ~+260 LOC прод (включая HTTPClient.swift), без новых тестов
  (state-machine на MenuBarController не покрыт — F006 в TECH_DEBT_AUDIT.md).
- VERSION 0.6.8 → 0.6.9, Info.plist build 15 → 16.

### Документация (этот /document-release)

- CHANGELOG: новый `[0.6.9]` entry — пользовательская секция + dev секция
  с разбивкой по 5 шагам + known limitations (subprocess cancellation).
- CLAUDE.md: file count check (45, корректно), MenuBarController size
  ~840 → ~1030, Networking теперь упоминает HTTPClient.swift, добавлено
  упоминание AudioRecorder per-session primitives.
- ARCHITECTURE.md: line count ~7820 → ~8130, карта модулей дополнена
  HTTPClient.swift, data flow обновлён (per-session primitives, epoch
  guard, deliverTranscriptionResult).
- README.md: статус 0.6.8 → 0.6.9 + строчка про sleep/wake recovery.
- decisions.md: ADR-015 — sleep/wake recovery, version в шапке 0.6.5 → 0.6.9.

---

## Что остаётся на ближайшее будущее

### Сразу после этой сессии

1. **build-dmg + GitHub release v0.6.9.**
   ```bash
   ./build.sh && ./build-dmg.sh
   gh release create v0.6.9 --latest WhisperHot-0.6.9.dmg
   ```
   По memory `feedback_auto_github_release.md` — это автоматически после
   version bump. Сделать сейчас.

2. **Запросить `sample WhisperHot 10` у пользователя при следующем freeze.**
   Codex явно сказал — sample не блокирует фикс, но это verification,
   которое подтвердит, что мы починили правильное (или укажет на 4-ю
   гипотезу, которую пропустили). Пока релиз закроет 3 из 3 архитектурных
   дефектов выявленных консультацией.

### Не сделано в этой сессии (намеренно)

#### Subprocess cancellation (P3 → P2 follow-up)
**Зачем.** `LocalWhisperProvider` и `LocalLLMProcessor` оборачивают `Process`
в `withCheckedThrowingContinuation` без cancellation handler. На willSleep
cancellation — Swift Task пометится cancelled, но `Process` продолжит работу.
Заметно только пользователям на Local Whisper / Local LLM — те, кто отрепортил
этот hang, на cloud-only.

**Как.** Заменить на `withTaskCancellationHandler { ... } onCancel: { proc.terminate() }`
обёртку, плюс корректный пропагейт SIGTERM в child. Возможно перейти на
`Subprocess` API из Swift 6 если переезжает minimum macOS target.

**Effort.** 1-2ч на обоих + тесты с URLProtocol-style mock subprocess.

#### State-machine tests на MenuBarController (F006)
**Зачем.** Сейчас правки state machine идут через manual smoke pass.
Регресс может проскочить незамеченным до пользовательского репорта.

**Как.** Mock `AudioRecorder` (через protocol) + mock `TranscriptionCoordinator`,
проверить epoch guard, sleep/wake transitions, isHotkeyRecorderArmed paths.
План в TECH_DEBT_AUDIT.md F006.

**Effort.** 2-3ч с тестами, после mock infrastructure.

### Из прошлого статус-handoff (всё ещё актуально)

- **F005 — Split SettingsView.swift** (1026 LOC, 6 tab-файлов). Hottest
  churn-файл. Без UI-тестов осторожно + manual QA после.
- **F001 backfill providers** — URLProtocol mock для OpenAI/Groq/PolzaAI/
  OpenRouter, plus PasteService guards refactor для testability.
- **F029 os.Logger** — 61 NSLog → структурированный os.Logger.
  Низкоприоритетно для personal app, но Console.app filtering за бесплатно.
  Особенно полезно сейчас, когда добавлены phase markers и state didSet —
  было бы category'ed.
- **Streaming транскрипция** — отдельный P3 XL deferred, plan в
  `docs/streaming-plan.md`.

---

## Контекст для следующей Claude-сессии

### Что НЕЛЬЗЯ забыть

1. **Codex review every stage** (memory). Перед commit'ом — `/codex` на diff.
2. **Sleep/wake handler'ы — НЕ полное покрытие.** Subprocess cancellation
   gap зафиксирован. Если пользователь отрепортит «hang после wake на Local
   Whisper / Local LLM» — это subprocess cancellation, отдельный фикс.
3. **`audioRecorder.resetAfterWake()` — non-blocking by design.** Если
   будешь править AudioRecorder и захочется добавить wait — НЕ добавляй
   в этот метод. Это и есть точка где sleep/wake recovery отказывается
   ждать. `stopRecording()` ждёт нормально (там можно — приходим из
   normal user-driven path).
4. **`transcriptionTask` ownership.** Любой новый код-путь, который
   запускает транскрипцию — должен сохранять handle в
   `self.transcriptionTask` И передавать epoch для stale-result guard.
   Иначе будет regression к старому ownership-gap.
5. **Per-session DispatchGroup/Queue в `ActiveSession`.** Не заменять
   на shared instance-level. Если нужен новый concurrency primitive —
   тоже на уровне `ActiveSession`, не выше.

### Файлы созданные / изменённые в этой сессии

Созданы:
- `Sources/WhisperHot/Networking/HTTPClient.swift` (Step 4)

Изменены:
- `Sources/WhisperHot/MenuBarController.swift` (steps 1-3, 5: state didSet, task ownership, sleep/wake handlers, helper)
- `Sources/WhisperHot/Audio/AudioRecorder.swift` (step 5: per-session primitives, resetAfterWake, processTapBuffer signature)
- `Sources/WhisperHot/Transcription/TranscriptionCoordinator.swift` (step 1: phase markers, Outcome.logTag)
- `Sources/WhisperHot/PostProcessing/LLMPostProcessor.swift` (step 4: HTTPClient.shared)
- `Sources/WhisperHot/Transcription/Providers/OpenAICompatibleSTTProvider.swift` (step 4: HTTPClient.shared)
- `Sources/WhisperHot/Transcription/Providers/OpenRouterAudioProvider.swift` (step 4: HTTPClient.shared)
- `VERSION`, `Resources/Info.plist` (PATCH bump 0.6.8 → 0.6.9, build 16)
- `CHANGELOG.md`, `CLAUDE.md`, `ARCHITECTURE.md`, `README.md`, `decisions.md` (этот document-release)

### Текущее состояние main

- 5 + 1 (docs) коммитов на origin/main (после push doc-commit)
- Working tree clean
- Tests 54/54 green в release
- VERSION = 0.6.9, Info.plist build = 16
- v0.6.9 GitHub release **ещё не создан** — следующий шаг
