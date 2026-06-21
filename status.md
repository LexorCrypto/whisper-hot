# STATUS — WhisperHot Developer ID release blocked on Apple notarization

Дата: 2026-06-07

## Что сделано

- Apple Developer ID Application certificate установлен и проверен:
  `Developer ID Application: Aleksei Supilin (3Z9833DUR3)`.
- Public key certificate совпадает с CSR:
  `/Users/aleksejsupilin/Documents/Cert/WhisperHot-DeveloperID.certSigningRequest`.
- Notary credentials сохранены в login Keychain profile:
  `WhisperHotNotary`.
- В `main` запушен commit `d5a7994`:
  `chore: add Developer ID notarization flow`.
- Документация обновлена и уже на GitHub:
  `README.md`, `ARCHITECTURE.md`, `CHANGELOG.md`.
- Release build и тесты прошли:
  - `swift build -c release` — OK.
  - `swift test` — 54/54 passed.
- Собран новый Developer ID signed DMG:
  `/Users/aleksejsupilin/Library/Caches/WhisperHot-build/WhisperHot-0.7.2.dmg`.
- `.app` подписан Developer ID + Hardened Runtime:
  `TeamIdentifier=3Z9833DUR3`, `flags=runtime`.
- DMG подписан Developer ID:
  `TeamIdentifier=3Z9833DUR3`.
- DMG SHA-256:
  `35ccae17c94f3f638f8b37b6a79bef0d4f2a792cffb6d7850f94f8c73711b17f`.

## Где заблокировались

- Apple Notary Service принял submission, но держит его в `In Progress`.
- Submission ID:
  `3951bc2b-58a3-43d0-b433-a8de04155abc`.
- Created date от Apple:
  `2026-06-07T09:12:12.744Z`.
- Первичный `./build-dmg.sh` был остановлен локально после долгого wait;
  серверный submission не отменён.
- Дополнительный bounded wait:
  `xcrun notarytool wait 3951bc2b-58a3-43d0-b433-a8de04155abc --keychain-profile WhisperHotNotary --timeout 5m --output-format json`
  завершился timeout после 300 секунд.

## Как продолжить

Проверить статус:

```bash
xcrun notarytool info 3951bc2b-58a3-43d0-b433-a8de04155abc \
  --keychain-profile WhisperHotNotary \
  --output-format json
```

Если статус станет `Accepted`, staple + validate:

```bash
DMG="$HOME/Library/Caches/WhisperHot-build/WhisperHot-0.7.2.dmg"
xcrun stapler staple -v "$DMG"
xcrun stapler validate -v "$DMG"
spctl -a -vv --type open --context context:primary-signature "$DMG"
```

После successful staple/validate заменить GitHub Release asset:

```bash
gh release upload v0.7.2 "$HOME/Library/Caches/WhisperHot-build/WhisperHot-0.7.2.dmg" --clobber
gh release view v0.7.2 --json url,name,assets
```

Если статус станет `Invalid`, забрать лог:

```bash
xcrun notarytool log 3951bc2b-58a3-43d0-b433-a8de04155abc \
  --keychain-profile WhisperHotNotary
```

## Всё ещё актуально

- GitHub Release `v0.7.2` пока НЕ заменён новым DMG.
- Новый DMG пока НЕ stapled/notarized для пользователей.
- Windows-порт принят как продуктовая цель, план:
  `docs/windows-support-plan.md`.
- Subprocess cancellation для `LocalWhisperProvider` /
  `LocalLLMProcessor` всё ещё отдельный follow-up.
- State-machine tests на `MenuBarController` всё ещё отсутствуют.
