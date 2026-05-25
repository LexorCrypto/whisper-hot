# Windows Support Plan

Дата: 2026-05-25
Статус: требование принято, реализация не начата

## Решение

WhisperHot должен получить Windows-версию, но текущий Swift/AppKit код
нельзя практически "дособрать" под Windows. Правильный путь — сохранить
текущую macOS-версию стабильной и параллельно вынести продуктовую логику
в платформенно-нейтральный слой с отдельными адаптерами для macOS и
Windows.

Целевая поддержка для первого Windows MVP:

- Windows 11 и Windows 10 22H2.
- x64 сначала, ARM64 после подтверждения базового MVP.
- Установка без прав администратора там, где это возможно.
- Подписанный installer и понятная privacy-модель.

## Почему не прямой порт Swift

Текущая кодовая база использует macOS API почти во всех системных
точках:

| Область | Сейчас на macOS | Что нужно на Windows |
|---------|------------------|----------------------|
| UI shell | AppKit, `NSWindow`, `NSPanel`, `NSStatusItem`, SwiftUI через `NSHostingView` | WinUI 3, Tauri window/tray или другой Windows shell |
| Микрофон | `AVAudioEngine` | WASAPI/Core Audio capture |
| Глобальные хоткеи | Carbon `RegisterEventHotKey`, `CGEventTap` для Fn | `RegisterHotKey`/`WM_HOTKEY` или low-level keyboard hook |
| Auto-paste | `NSPasteboard` + `CGEventPost` | Windows Clipboard + `SendInput` |
| Активное приложение/контекст | `NSWorkspace`, Accessibility/AX | foreground window APIs + UI Automation |
| Секреты | macOS Keychain | Windows Credential Manager или DPAPI |
| Автозапуск | `SMAppService.mainApp` | Startup Apps, registry или scheduled task |
| Локальный whisper | Homebrew + локальные пути | bundled binaries, winget/installer flow или ручной path |
| Распространение | `.app`/DMG, Gatekeeper/TCC | MSIX/installer, code signing, Windows privacy prompts |

Из-за этого Windows-поддержка — это не флаг в `Package.swift`, а
отдельная платформенная реализация.

## Что можно переиспользовать

- Продуктовую модель: "нажал hotkey -> записал WAV -> STT -> cleanup ->
  словарь замен -> clipboard/auto-paste".
- Контракты провайдеров STT/LLM и формы HTTP-запросов.
- Пресеты post-processing и контекстный роутинг как идею.
- Схему настроек, словарь замен, историю транскриптов и privacy policy.
- UX главного окна: Dashboard / History / Settings / Setup.
- Подходы к ошибкам: clipboard-only fallback, понятная причина отказа
  auto-paste, сохранение текста даже при сбое вставки.

## Рекомендуемый стек

### Вариант A: Tauri v2 + Rust core + web UI

Рекомендованный путь, если мы хотим со временем иметь общий desktop shell
для macOS и Windows.

Плюсы:

- У Tauri v2 есть официальный набор desktop-плагинов: clipboard,
  global shortcut, store, shell/process, updater, tray и другие.
- Rust хорошо подходит для системных адаптеров, subprocess management,
  WASAPI/Win32 bindings и shared core.
- Меньше runtime-вес, чем у Electron.
- Можно начать с Windows MVP, не ломая текущий macOS Swift app.

Минусы:

- Нужно заново собрать UI shell.
- Текущий Swift/AppKit код не переедет автоматически.
- Для микрофона, foreground app, secure storage и paste всё равно нужны
  аккуратные platform adapters.

### Вариант B: WinUI 3 / C# Windows-first

Подходит, если цель — быстрее получить максимально нативную Windows
версию без немедленной унификации с macOS.

Плюсы:

- Нативный Windows UX, Fluent controls, хорошая интеграция с Win32.
- Удобнее для Windows-only polish и installer story.

Минусы:

- Две UI-кодовые базы.
- Больше риска расхождения фич между macOS и Windows.

### Вариант C: Electron

Самый быстрый путь к переносимому UI, но для WhisperHot это спорный
компромисс: приложение должно быть лёгкой always-on утилитой с горячими
клавишами, записью микрофона и системным clipboard/paste behavior.
Electron можно держать как fallback, но не как первый выбор.

### Вариант D: Swift on Windows

Не рекомендуется. Swift как язык может существовать на Windows, но
WhisperHot зависит не от языка, а от AppKit/AVFoundation/Keychain/TCC.
Эти API на Windows отсутствуют.

## Предлагаемая архитектура

```text
whisperhot-core
  Providers: OpenAI, OpenRouter, Groq, Polza.ai, local whisper contract
  Pipeline: transcription -> word replacement -> post-processing
  Models: preferences, history entry, context rule, provider config
  Tests: golden cases for routing, cleanup, replacement, provider errors

platform-macos
  AudioCapture(AVAudioEngine)
  GlobalHotkey(Carbon/CGEventTap)
  ClipboardPaste(NSPasteboard/CGEventPost)
  ActiveAppContext(NSWorkspace/AX)
  SecretStore(Keychain)
  Autostart(SMAppService)

platform-windows
  AudioCapture(WASAPI)
  GlobalHotkey(RegisterHotKey/WM_HOTKEY)
  ClipboardPaste(Clipboard/SendInput)
  ActiveAppContext(Foreground window/UI Automation)
  SecretStore(Credential Manager/DPAPI)
  Autostart(Startup Apps/registry/scheduled task)

ui-shell
  Dashboard
  History
  Settings
  Setup/Permissions
  Tray/menu controller
```

Главное правило: бизнес-логика не должна напрямую знать о
`NSPasteboard`, `AVAudioEngine`, `RegisterHotKey`, `SendInput` или
Keychain. Она вызывает интерфейсы `AudioCapture`, `GlobalHotkey`,
`ClipboardPaste`, `ActiveAppContext`, `SecretStore`, `Autostart`.

## Windows MVP

Первый Windows MVP должен доказать не весь feature parity, а самое
рискованное ядро:

- Главное окно с Dashboard / Settings.
- System tray icon.
- Глобальный hotkey start/stop.
- Запись микрофона в PCM/WAV.
- Один cloud STT provider: OpenAI или Groq.
- Clipboard write и auto-paste в активное приложение.
- Clipboard-only fallback, если paste заблокирован.
- API key storage через Windows secure storage.
- Минимальная история последних транскриптов.
- Installer/dev build, который можно дать тестеру.

Не включать в первый spike:

- Local whisper installer.
- Полный context routing.
- Fn-key аналоги.
- Streaming transcription.
- Полный updater.
- Историю с production-grade encryption.

## Риски Windows

- `SendInput` может быть заблокирован UIPI, если целевое приложение
  запущено с более высоким integrity level. Для таких случаев нужен
  явный clipboard-only fallback.
- Глобальные hotkeys часто конфликтуют с системой и приложениями.
  Нужен UI для смены сочетания и диагностика "hotkey занят".
- Windows Clipboard глобален для сессии пользователя. Это требует такой
  же privacy-позиции, как на macOS: транскрипт может увидеть clipboard
  manager.
- UI Automation не даст одинаково надёжный direct insert во всех
  приложениях. Базовый generic path должен оставаться clipboard +
  synthetic paste.
- Local whisper на Windows добавит вопросы поставки бинарей, моделей,
  антивирусных false positives и размера installer.
- Windows audio device changes надо тестировать отдельно: Bluetooth,
  USB-микрофоны, Teams/Zoom, sleep/wake.

## Дорожная карта

1. Зафиксировать platform contracts в текущем репозитории.
   Минимум: документировать интерфейсы и golden behavior для pipeline.
2. Сделать отдельный Windows spike на выбранном стеке.
   Цель spike: hotkey -> WASAPI recording -> cloud STT -> paste.
3. После spike выбрать окончательный стек.
   По умолчанию: Tauri v2 + Rust, если spike не вскроет блокеры.
4. Вынести shared contracts и тестовые фикстуры.
   Не начинать большой rewrite macOS до подтверждения Windows MVP.
5. Дособрать Windows MVP до private alpha.
6. Добавить parity-фичи: история, post-processing, context routing,
   local whisper, updater, launch at login, signed installer.
7. Отдельно решить, оставляем ли macOS native Swift app или мигрируем
   обе платформы в общий shell.

## Источники для платформенных решений

- Tauri v2 plugin table: <https://v2.tauri.app/plugin/>
- WinUI 3 overview: <https://learn.microsoft.com/windows/apps/winui/winui3/>
- Windows `RegisterHotKey`: <https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-registerhotkey>
- Windows WASAPI overview: <https://learn.microsoft.com/windows/win32/coreaudio/wasapi>
- Windows Clipboard overview: <https://learn.microsoft.com/windows/win32/dataxchg/about-the-clipboard>
- Windows `SendInput`: <https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-sendinput>
- Windows UI Automation overview: <https://learn.microsoft.com/windows/win32/winauto/uiauto-uiautomationoverview>
