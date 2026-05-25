# STATUS — WhisperHot v0.7.2 emergency Keychain hotfix

Дата: 2026-05-25
Версия: 0.7.2 (emergency patch: stop Keychain prompt-loop)

## Что произошло

- `0.7.1` выпущен как Keychain ACL patch, но на живых user items оказался
  unsafe: macOS после ввода login keychain password снова и снова показывала
  prompt. Пользователь ввёл пароль 10+ раз, loop не прекращался.
- Запущенный `/Applications/WhisperHot.app` был найден и к моменту kill уже
  завершился; повторная проверка `ps` показала, что процесс больше не живёт.
- Вывод: автоматический `kSecAttrAccess` repair на read/update нельзя делать
  на launch path.

## Что изменено в 0.7.2

- Полностью убран risky ACL repair из `Keychain.swift`:
  `Darwin` import, dynamic lookup `SecAccessCreate`, `kSecAttrAccess` на
  add/update и post-read `SecItemUpdate(kSecAttrAccess)`.
- Главное окно больше не читает API key при запуске:
  `MainWindowModel` и Setup provider readiness работают в no-Keychain mode
  для cloud-провайдеров.
- 0.75s timer по-прежнему обновляет recording/permissions state, но не
  touches Keychain.
- `CHANGELOG.md`, `README.md`, `ARCHITECTURE.md`, `decisions.md`,
  `VERSION`, `Info.plist` обновлены под `0.7.2` / build `19`.
- `0.7.1` помечен как superseded by `0.7.2`.

## Проверка перед релизом

- Нужно прогнать `swift build -c release`.
- Нужно прогнать `swift test`.
- Нужно прогнать `git diff --check`.
- После commit/push собрать `WhisperHot-0.7.2.dmg`, проверить
  `hdiutil verify`, создать GitHub Release `v0.7.2` и сделать latest.

## Важное для пользователя

- До установки `0.7.2` не запускать `0.7.1`.
- Если prompt-loop снова появится, сначала остановить процесс WhisperHot.
- `0.7.2` должен открывать главное окно без Keychain prompt на launch.
  Prompt может появиться только при явном открытии Providers/Settings или
  при транскрипции, где API key реально нужен.

## Всё ещё актуально

- Windows-порт принят как продуктовая цель, план:
  `docs/windows-support-plan.md`.
- Subprocess cancellation для `LocalWhisperProvider` / `LocalLLMProcessor`
  всё ещё отдельный follow-up.
- State-machine tests на `MenuBarController` всё ещё отсутствуют.
