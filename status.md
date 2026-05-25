# STATUS — WhisperHot main-window MVP

Дата: 2026-05-25
Версия: 0.7.0 (minor bump: полноценное главное окно)

## Что изменилось

- WhisperHot больше не запускается как `LSUIElement`/accessory-only app.
  `Resources/Info.plist` больше не содержит `LSUIElement`, `main.swift`
  ставит `.regular`, приложение появляется в Dock и открывает главное окно.
- `AppDelegate` теперь создаёт пару:
  `MenuBarController(showsOnboardingAutomatically: false)` +
  `MainWindowController`, показывает главное окно на launch и при Dock
  reopen.
- Menu bar остаётся быстрым контроллером. Добавлен пункт
  `Open WhisperHot`, который возвращает главное окно.
- Новое главное окно (`Sources/WhisperHot/MainWindow/`):
  Dashboard + настройки первого уровня: Recording / Providers /
  Post-processing / Hotkey / History & Privacy / Updates, плюс History
  и Setup.
  Dashboard показывает текущий STT route, модель, хоткей, состояние
  post-processing/context/history/autopaste/local fallback.
- Кнопка записи из Dashboard не пишет в само окно: перед стартом она
  прячет главное окно, возвращает фокус в предыдущее приложение и только
  потом вызывает `MenuBarController.toggleRecordingFromInterface`.
- `HistoryView` вынесен в переиспользуемый `TranscriptHistoryView`, чтобы
  встроенная вкладка History и старое отдельное окно использовали один UI.
- `SettingsWindowController` больше не возвращает приложение в
  `.accessory` при закрытии. Settings/History/Onboarding/Main window
  очищают stale `previousApp`, если открыты из самого WhisperHot.
- `SettingsView` получил embedded-режим: в главном окне показывается
  только выбранная секция настроек без вложенного sidebar, а отдельное
  окно Settings по-прежнему открывается со своим sidebar.
- После window-only visual QA основного окна sidebar label
  `History & Privacy` в главном shell укорочен до `Privacy` /
  `Приватность`, чтобы не обрезаться на дефолтной ширине окна.
- Setup теперь показывает не только Microphone / Accessibility /
  Input Monitoring, но и готовность текущего STT-провайдера: cloud
  API-key в Keychain или local whisper.cpp binary+model.
- Setup polished after QA: готовые строки больше не показывают серые
  disabled-кнопки, вместо них справа компактный зелёный бейдж `Готово`.
- README обновлён: больше не говорит, что приложение живёт только в
  menu bar.

## Проверка

- `swift build -c release` — OK.
- `swift test` — 54/54 passed.
- `./build.sh` — OK, подписанный bundle:
  `~/Library/Caches/WhisperHot-build/WhisperHot.app`.
- Window-only visual QA главного окна — OK: один foreground-процесс,
  одно окно `WhisperHot`, Dashboard/sidebar/primary actions визуально
  рендерятся, sidebar без обрезки. Full-screen screenshot намеренно не
  делался; использовался только снимок окна WhisperHot.
- Click-through QA без записи микрофона — OK:
  sidebar selection открывает Dashboard / Recording / Providers /
  Post-processing / Hotkey / Privacy / Updates / History / Setup;
  закрытие главного окна оставляет приложение живым; повторный `open`
  возвращает окно; status-menu пункт `Открыть WhisperHot` тоже
  возвращает окно; Setup визуально показывает `Можно записывать`,
  Microphone/Accessibility/Input Monitoring и готовность Groq key.
- Sensitive recording QA — OK с согласия пользователя:
  новый пустой TextEdit-документ использовался как безопасная цель
  auto-paste; запись стартовала из Dashboard, тестовая фраза была
  проиграна системным `say`, остановка через status-menu; Groq вернул
  транскрипт, auto-paste вставил его в TextEdit. Clipboard напрямую не
  читался, чтобы не захватить чужие данные.
- Pre-bump DMG smoke — OK:
  pre-bump `~/Library/Caches/WhisperHot-build/WhisperHot-0.6.9.dmg`,
  895 KB, `hdiutil verify` reports checksum VALID. По пользовательскому
  порядку финальный `WhisperHot-0.7.0.dmg` собирается только после
  document-release, commit и push.

## Важные нюансы для следующей сессии

- 2026-05-25 пользователь добавил обязательное направление:
  WhisperHot должен поддерживать Windows. Это не реализовано в коде;
  текущий Swift/AppKit package остаётся macOS-only. Дорожная карта и
  рекомендуемый подход зафиксированы в
  `docs/windows-support-plan.md`: Windows-порт через platform adapters,
  предпочтительно Tauri v2 + Rust spike, без немедленного rewrite текущего
  macOS приложения.
- Старый авто-Onboarding popup отключён на launch. Первичный путь теперь —
  вкладка Setup в главном окне, но отдельное окно Permissions & Onboarding
  всё ещё доступно из menu bar. Dashboard теперь ведёт во встроенный Setup.
- Dashboard start-button зависит от `previousApp`, сохранённого при показе
  главного окна. В нормальном сценарии это целевое приложение; если
  пользователь стартует запись сразу после launch без явного target app,
  auto-paste может не найти валидную цель и оставит текст в clipboard.
- Dashboard recording + auto-paste smoke уже пройден. Отдельно не
  проверялся физический Fn/hotkey нажатием с клавиатуры; в QA запись
  стартовала из Dashboard, остановка была через status-menu.

## Всё ещё актуально из прошлого handoff

- v0.7.0 docs/version bump подготовлен; commit/push идут перед финальной
  сборкой DMG.
- Subprocess cancellation для `LocalWhisperProvider` / `LocalLLMProcessor`
  всё ещё отдельный follow-up.
- State-machine tests на `MenuBarController` всё ещё отсутствуют.
