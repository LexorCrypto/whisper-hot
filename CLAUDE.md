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

- `Sources/WhisperHot/` — 40 Swift файлов (~8000 строк)
- `Sources/WhisperHot/MenuBarController.swift` — state machine hub (819+ строк)
- `Sources/WhisperHot/ContextRouter/` — контекстный роутинг (bundle ID → preset)
- `Sources/WhisperHot/PostProcessing/` — LLM пост-обработка (4 провайдера)
- `Sources/WhisperHot/Indicator/` — индикаторы записи (4 стиля)
- `Sources/WhisperHot/Settings/` — Preferences + SettingsView (sidebar, 5 секций)
- `Sources/WhisperHot/Localization/` — L10n.swift (русский/английский UI)
- `Sources/WhisperHot/LocalSetup/` — WhisperInstaller + UpdateChecker
- `Resources/Sounds/` — кастомные AIFF звуки
- `Resources/WhisperHot.icns` — иконка приложения

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
