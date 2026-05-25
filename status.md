# STATUS — WhisperHot v0.7.1 Keychain patch

Дата: 2026-05-25
Версия: 0.7.1 (patch: Keychain ACL repair)

## Что изменилось

- После установки GitHub DMG `0.7.0` пользователь подтвердил рабочий
  main-window релиз, но macOS каждый раз заново просила login keychain
  password и `Разрешить всегда` для API keys.
- Подпись установленного `/Applications/WhisperHot.app` проверена:
  designated requirement стабилен и завязан на
  `com.aleksejsupilin.WhisperHot` + leaf certificate
  `3e456ffaf9ca555c650522806ffb010acc8c528f`. Значит root cause не в
  текущем DMG signing, а в старых Keychain item ACL и слишком частом
  Keychain polling из нового main window.
- `Keychain.saveRaw` теперь для production service
  `com.aleksejsupilin.WhisperHot` создаёт/обновляет items с явным
  `kSecAttrAccess`.
- `Keychain.readRaw` после успешного чтения production item делает
  best-effort ACL repair, чтобы старые ad-hoc-era items после одного
  `Разрешить всегда` перестали спрашивать заново.
- Тестовые service-id не получают ACL override, чтобы XCTest не провоцировал
  системные Keychain prompts.
- `MainWindowModel.refresh` получил `includeProviderSetup`: 0.75s UI timer
  больше не читает API key. Provider readiness обновляется на open,
  settings changes и Keychain save/delete.
- `CHANGELOG.md`, `README.md`, `ARCHITECTURE.md`, `decisions.md`,
  `VERSION`, `Info.plist` обновлены под `0.7.1` / build `18`.

## Проверка

- `swift build -c release` — OK, без warnings.
- `swift test` — 54/54 passed.
- `git diff --check` — OK.

## Ожидаемое поведение

- При первом запуске `0.7.1` macOS может ещё один раз спросить доступ к
  старым Keychain items. После `Разрешить всегда` WhisperHot должен
  repair-нуть ACL, и следующие сборки с тем же `whisper-hot-local`
  сертификатом не должны повторять prompt.

## Следующие шаги после commit/push

- Собрать `WhisperHot-0.7.1.dmg` только после commit/push, по
  пользовательскому порядку релиза.
- Проверить `hdiutil verify`.
- Создать tag/release `v0.7.1`, загрузить DMG asset и пометить latest.

## Всё ещё актуально из прошлого handoff

- Windows-порт принят как продуктовая цель, план:
  `docs/windows-support-plan.md`.
- Subprocess cancellation для `LocalWhisperProvider` / `LocalLLMProcessor`
  всё ещё отдельный follow-up.
- State-machine tests на `MenuBarController` всё ещё отсутствуют.
