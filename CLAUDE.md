# WhisperHot

macOS menu bar приложение для speech-to-text. Swift 5.9 / SwiftPM, zero dependencies,
macOS 13.0+, Apple Silicon (ARM64).

## Сборка и запуск

```bash
swift build -c release      # компиляция
./build.sh                  # подписанный .app bundle
./build-dmg.sh              # DMG для распространения
```

## Структура проекта

- `Sources/WhisperHot/` — 43 Swift файла (~7680 строк), library target WhisperHotLib
- `Sources/WhisperHotApp/` — thin executable (main.swift)
- `Sources/WhisperHot/MenuBarController.swift` — state machine hub (~840 строк), menubar items: Provider submenu + Auto-offline toggle (ADR-014) + Settings/History/About
- `Sources/WhisperHot/ContextRouter/` — контекстный роутинг (bundle ID → preset)
- `Sources/WhisperHot/PostProcessing/` — LLM пост-обработка (4 провайдера)
- `Sources/WhisperHot/Indicator/` — индикаторы записи (5 стилей, включая Studio)
- `Sources/WhisperHot/Settings/` — Preferences + SettingsView (sidebar, 5 секций)
- `Sources/WhisperHot/Localization/` — L10n.swift (русский/английский UI)
- `Sources/WhisperHot/LocalSetup/` — WhisperInstaller + UpdateChecker
- `Sources/WhisperHot/Transcription/FallbackTranscriptionService.swift` — offline fallback wrapper, опциональный timeout race (ADR-014)
- `Resources/Sounds/` — кастомные AIFF звуки
- `Resources/WhisperHot.icns` — иконка приложения (Voice → Text logo)
- `docs/logo-concepts/` — design exploration: 6 концептов + showcase HTML
- `scripts/make-icns.sh` — конвертер 1024×1024 PNG → .icns

## Маршрутизация навыков (Skill routing)

Когда запрос пользователя совпадает с доступным навыком, ВСЕГДА вызывай его через
Skill tool КАК ПЕРВОЕ действие. НЕ отвечай напрямую, НЕ используй другие инструменты первыми.
Навык имеет специализированные процессы, которые дают лучшие результаты.

Правила маршрутизации:
- Идеи продукта, "стоит ли это делать", мозговой штурм → invoke office-hours
- Баги, ошибки, "почему это сломалось", 500 ошибки → invoke investigate
- Деплой, пуш, создать PR → invoke ship
- QA, тестирование, поиск багов → invoke qa
- Код-ревью, проверить мой дифф → invoke review
- Обновить документацию после релиза → invoke document-release
- Еженедельная ретроспектива → invoke retro
- Дизайн-система, бренд → invoke design-consultation
- Визуальный аудит, полировка дизайна → invoke design-review
- Архитектурный обзор → invoke plan-eng-review
- Сохранить прогресс, чекпоинт, возобновить → invoke checkpoint
- Качество кода, проверка здоровья → invoke health
