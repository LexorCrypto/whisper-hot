# Session — 2026-07-21 — индикатор: цель вставки + 2 стиля + always-on-top, релиз v0.9.0

## Сделано

### Индикатор записи (Sources/WhisperHot/Indicator/)
- **Цель вставки в индикаторе.** `IndicatorViewModel` получил `@Published destination`;
  `IndicatorController.show(destination:)` прокидывает его. `Minimal`/`Medium` рисуют
  таймер `mm:ss` + «→ цель» с обрезкой длинных имён (`lineLimit(1)` + `truncationMode(.tail)`
  + `maxWidth`).
- **Честный ярлык.** `MenuBarController.pasteDestinationLabel()` возвращает имя приложения
  только при `autoPaste && AXIsProcessTrusted() && recordingTarget?.localizedName`, иначе
  `L10n.indicatorClipboardTarget` («Буфер обмена» / «Clipboard») — совпадает с контрактом
  PasteService (pasteboard всегда заполняется; Cmd+V только при живой цели + Accessibility).
  Добавлен `import ApplicationServices` для `AXIsProcessTrusted()`.
- **Сокращение до 2 стилей.** `IndicatorStyle` → `minimal` / `medium`; `case large` и файл
  `LargeIndicatorView.swift` удалены. Сохранённое `large` → `.minimal` (чистый cutover:
  и `Preferences.indicatorStyle`, и `@AppStorage` резолвят неизвестный rawValue в `.minimal`
  — рантайм и пикер согласованы, миграция не нужна).
- **Always-on-top при записи.** `IndicatorController` держит панель поверх: `.statusBar`
  level + ре-ассерт `orderFrontRegardless()` по `NSWorkspace.didActivateApplicationNotification`
  (`installKeepOnTopObserver()` в `show()` с guard против двойной подписки,
  `removeKeepOnTopObserver()` в `hide()`).

### Сайт + документация
- `landing/lib/content.ts`: карточка «3 стиля» → «2 стиля индикатора» + честная
  формулировка (таймер + цель: активное приложение при авто-вставке, иначе буфер).
  `next build` зелёный.
- README / ARCHITECTURE / CLAUDE.md синхронизированы (2 стиля, destination, файлы Indicator/).

## Проверка
- `swift build` + `swift test` — **54 теста зелёные**.
- Визуальный рендер обоих стилей (Hermes + длинное имя) через `ImageRenderer` — таймер,
  «→ цель» и обрезка `…` подтверждены; временный харнесс удалён.
- Codex-ревью release-prep диффа (bump) — **GREEN**.
- Per-commit Codex-аудит session-коммитов **не завершился** (модель `gpt-5.6-sol`
  недоступна для аккаунта + 300s timeout дефолтной модели); gate закрыт прямой
  верификацией — см. `docs/operations/audits/{ef7650f,910332f,601eac2}-codex-audit.md`.
- `.dmg`: Gatekeeper `accepted`, `source=Notarized Developer ID`, staple validated.

## Релиз
- **v0.9.0** (CFBundleVersion 22). Коммиты: `ef7650f` (destination + 2 стиля),
  `910332f` (always-on-top), `601eac2` (bump). Тег `v0.9.0` запушен атомарно.
- GitHub Release: https://github.com/LexorCrypto/whisper-hot/releases/tag/v0.9.0
  (latest, ассеты `WhisperHot-0.9.0.dmg` + `.sha256`).

## Известное ограничение
- Always-on-top: ре-ассерт срабатывает на активацию приложения, не на новое окно внутри
  уже активного приложения; `.statusBar` по дизайну ниже системных popup/menu. Покрыто:
  переключение приложений, Spaces, fullscreen другого приложения. Абсолютной гарантии
  против всех оконных уровней без GUI-проверки edge-кейсов нет (screenSaver-level намеренно
  не выбран — перекрыл бы системный UI).

## SHA-256 артефакта
- v0.9.0 DMG: `699aeb4f1a430d353556cada1a9b08e6fe14c15951525ebf527515bde1a93df7`

## Следующие шаги
- Backlog (issue #4): Windows-порт / subprocess cancellation / MenuBar state-machine тесты.
- Опционально: GUI-проверка always-on-top в fullscreen/popup edge-кейсах.
